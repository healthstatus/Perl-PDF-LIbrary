#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package Field;

use Carp;
use Shape;
use ImageContent;
use Appearance;

@ISA = qw(Annot);

%Field::AbbrNames = (
	'Button'	=> 'Btn',
	'Radio'		=> 'Btn',
	'CheckBox'	=> 'Btn',
	'Select'	=> 'Ch',
	'Combo'		=> 'Ch',
	'Text'		=> 'Tx',
	'TextArea'	=> 'Tx',
	'Password'	=> 'Tx',
	'List'		=> 'Ch',
);

%Field::FieldFlags = (
# Common
	'ReadOnly'	=> 1,
	'Required'	=> 2,
	'NoExport'	=> 4,
# Field type flags
	'Button'	=> 0x10000,
	'Text'		=> 0,
	'TextArea'	=> 0x1000,
	'Password'	=> 0x2000,
	'List'		=> 0,
	'Select'	=> 0,
	'Radio'		=> 0x8000,
	'CheckBox'	=> 0,
# Radio button only
	'NoToggleOff' => 0x4000,
# Listbox only
	'Combo'		=> 0x20000,
	'Sorted'	=> 0x80000,
# Combo box only
	'Edit'		=> 0x40000,
);

%Field::SubmitFlags = (
	'FDF'	=> 4,	# This flag is set by default
	'Get'	=> 8,
	'Coord'	=> 16,
	'XFDF'	=> 32,	# XFDF, Annots, and AsPDF: v3.0 addition
	'Annots' => 128,
	'AsPDF'	=> 256,
);

%Field::ZaDbSigns = (
	'Check'	=> '4',
	'Cross'	=> '8',
	'Diamond' => chr( 169 ),
	'Star'	=> 'H',
	'Square' => 'n',
	'Arrow'	=> chr( 220 ),
	'Hand'	=> '+',
	'Heart'	=> chr( 170 ),
);

%Field::FieldCodes = (
	'Button'	=> \&btnCode,
	'Text'		=> \&txCode,
	'TextArea'	=> \&txCode,
	'Password'	=> \&txCode,
	'CheckBox'	=> \&checkCode,
	'Radio'		=> \&checkCode,
	'List'		=> \&chCode,
	'Select'	=> \&chCode,
	'Combo'		=> \&chCode,
);

%Field::RadioButtons = ( );	# Used to hold radio button groups.

sub new {
	my( $class, $rect, $type, $attr ) = @_;
	my $this = new Annot( $rect, 'Widget', $attr );
	bless $this, $class;
	if( !$Field::FieldCodes{$type} ){
		croak "$type is not a valid widge type";
	}
	$this->{DesiredType} = $type;
	$this->{FieldType} = $Field::AbbrNames{$type};
	if( !exists $attr->{Name} ){
		croak "A Name must be defined for a form field";
	}
	$this->{FieldName} = $attr->{Name};
	$this->{Parent} = undef;
	$this->{Kids} = [ ];
	$this->{XML} = [ ];
	$this->{Flags} = $Field::FieldFlags{$type};
	for( qw(ReadOnly Required NoExport NoToggleOff) ){
		next unless defined $attr->{$_};
		push( @{$this->{XML}}, qq{$_="1"} );
		$this->{Flags} |= $Field::FieldFlags{ $_ };
	}
	for( qw(Value Tips) ){
		next unless defined $attr->{$_};
		# TextArea fields will store the text within tags.
		push( @{$this->{XML}}, qq{$_="} . &PDF::escXMLChar( $attr->{$_} ) . '"' ) unless( $type eq 'TextArea' );
		$this->{$_} = $attr->{$_};
	}
	$this->{MakeCodeSegment} = $Field::FieldCodes{ $type };

	for( qw(BorderWidth BorderDash BorderStyle BorderColor BgColor FontFace FontSize FontColor) ){
		next unless defined $attr->{$_};
		push( @{$this->{XML}}, qq{$_="} . &PDF::escXMLChar( $attr->{$_} ) . '"' );
	}
	$this->{BorderWidth} = ( defined $attr->{BorderWidth}? $attr->{BorderWidth}: 1 );
	$this->{BorderDash} = $attr->{BorderDash};
	if( $attr->{BorderDash} ){
		$this->{BorderStyle} = 'D';
	}
	if( defined $attr->{BorderStyle} ){
		$this->{BorderStyle} = { qw(Solid S Dashed D Beveled B Inset I Underline U None N) }->{ $attr->{BorderStyle} };
	}
	$this->{BorderColor} = ( $attr->{BorderColor} || ( $type eq 'Button'? '': 'Black' ) );
	$this->{BgColor} = ( $attr->{BgColor} || ( $type eq 'Button'? 'LightGray': 'White' ) );
	if( !$this->{BorderStyle} ){
		if( defined $attr->{BorderWidth} && !$attr->{BorderWidth} ){
			$this->{BorderStyle} = 'N';
		} else {
			$this->{BorderStyle} = ( $type eq 'Button'? 'B': 'S' );
		}
	}
	if( $this->{BorderStyle} eq 'D' ){
		$this->{BorderDash} ||= 'Dashed';
	}

	if( defined $attr->{FontFace} || $type eq 'Radio' || $type eq 'CheckBox' ){
		$this->{FontFace} = ( $attr->{FontFace} || 'ZapfDingbats' );
		$this->{Font} = $PDF::root->getFont( $this->{FontFace}, 'PDFDocEncoding' );
		$this->{FontName} = $this->{Font}->{Name};
		$PDF::root->getAcroForm( )->{UsedFonts}->{ $this->{FontName} } = 1;
	} else {
		$this->{Font} = $PDF::root->getAcroForm( )->{DefaultFont};
		$this->{FontFace} = $this->{Font}->{FontPtr}->{BaseFont};
		$this->{FontName} = $this->{Font}->{Name};
	}
	my $FontBBox = $this->{Font}->{FontPtr}->{FontDescriptor}->{FontBBox};
	if( defined $attr->{FontSize} ){
		if( $attr->{FontSize} ){	# If font size is non-zero, use it
			$this->{FontSize} = $attr->{FontSize};
		} elsif( $type ne 'List' && $type ne 'Select' ){	# Otherwise, interpretted as "auto" -- font size fits in the box (except for list boxes)
			$this->{FontSize} = sprintf( "%.4f", ( $rect->height( ) - $this->{BorderWidth} * 2 *
				( $type eq 'Button' && { qw(I 1 B 1) }->{ $this->{BorderStyle} }? 2: 1 ) ) / ( $FontBBox->[3] - $FontBBox->[1] ) * 1000 );
		}
	} else {
		$this->{FontSize} = 12;
	}
	$this->{FontColor} = $attr->{FontColor} || 'Black';
	$this->{DefaultApp} = qq{/$this->{FontName} $this->{FontSize} Tf } . join( ' ', &Color::tellColor( $this->{FontColor} ), { qw(CMYK k RGB rg Gray g) }->{ $PDF::root->{Prefs}->{ColorSpace} || 'RGB' } );

	if( $type eq 'Button' ){
		for( qw(Caption Highlight Icon IconPos Action Url JS FDF Coord Get Dest File XFDF Annots AsPDF) ){
			next unless( defined $attr->{$_} );
			push( @{$this->{XML}}, qq{$_="} . &PDF::escXMLChar( $attr->{$_} ) . '"' );
		}
		$this->{Caption} = defined $attr->{Caption}? $attr->{Caption}: $this->{FieldName};
		$this->{Highlight} = { qw(Push P Invert I Outline O None N) }->{ $attr->{Highlight} || 'Push' };
		$this->{Highlight} ||= 'P';
		if( $attr->{Icon} ){	# File name, please
			$this->{Icon} = new ImageContent( $attr->{Icon}, 0, 0, {'Inline'=>1} );
			$this->{IconPos} = $attr->{IconPos};
			if( $attr->{IconPos} eq 'Fit' || $attr->{IconPos} eq 'Stretch' ){
				my( $rx, $ry ) = (
					$this->{Icon}->{Width} / ( $this->{rect}->{Width} - $this->{BorderWidth} * 2 ),
					$this->{Icon}->{Height} / ( $this->{rect}->{Height} - $this->{BorderWidth} * 2 )
				);
				if( $attr->{IconPos} eq 'Fit' ){
					$this->{Icon}->{DisplayWidth} /= &PDF::max( $rx, $ry );
					$this->{Icon}->{DisplayHeight} /= &PDF::max( $rx, $ry );
				} else {
					$this->{Icon}->{DisplayWidth} /= $rx;
					$this->{Icon}->{DisplayHeight} /= $ry;
				}
			}
		}
		$this->{AP} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
		$this->appendChild( $this->{AP} );
		if( $PDF::root->getAcroForm( )->{Theme} eq 'WinXP' ){
			$this->{BorderColor} = ( $attr->{BorderColor} || '185284' );
			$this->{BorderWidth} = ( $attr->{BorderWidth} || 2 );
			bless $this->{AP}, 'WinXPAppearance';
		}
		$this->{AP}->showButton( );
		if( $this->{Highlight} eq 'P' ){
			$this->{APDown} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
			$this->appendChild( $this->{APDown} );
			if( $PDF::root->getAcroForm( )->{Theme} eq 'WinXP' ){
				bless $this->{APDown}, 'WinXPAppearance';
			}
			$this->{APDown}->showButton( 1 );
		}
		$this->{APRollOver} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
		$this->appendChild( $this->{APRollOver} );
		if( $PDF::root->getAcroForm( )->{Theme} eq 'WinXP' ){
			bless $this->{APRollOver}, 'WinXPAppearance';
			$this->{APRollOver}->showButton( 2 );
		}
		for( qw(Action JS FDF Coord Get XFDF Annots AsPDF) ){
			next unless( defined $attr->{$_} );
			$this->{$_} = $attr->{$_};
		}
		$this->{Action} ||= '';
		if( $this->{Action} eq 'Submit' ){
			$this->{Url} = $attr->{Url} || $PDF::root->getAcroForm( )->{Url};
		} elsif( $this->{Action} eq 'FlipPage' ){
			$this->{Dest} = ( { '<' => 'Prev', '<<' => 'First', '>>' => 'Last', '>' => 'Next' }->{ $attr->{Dest} } || 'Next' ) . 'Page';
		} elsif( $this->{Action} eq 'Goto' ){
			# For remote go-to, $this->{Page} is a page number; otherwise it is a ref to a Page obj (as of v2.4) or the name of a Page (as of v2.5)
			# In either case, if $attr->{Page} is not defined, goes to the first page.
			if( defined $attr->{File} ){
				$this->{File} = $attr->{File};
				$this->{Page} = ( $attr->{Page} || 0 );
				push( @{$this->{XML}}, qq{Page="$attr->{Page}"} );
			} else {
				if( !defined $attr->{Page} ){	# If $attr->{Page} is absent, use the first page.
					$this->{Page} = $PDF::PageObjs[0];
				} elsif( ref( $attr->{Page} ) eq 'Page' ){		# In this case, $attr->{Page} is a Page object.
					$this->{Page} = $attr->{Page};
				} elsif( $attr->{Page} =~ /^\d+$/ && $PDF::PageObjs[ $attr->{Page} ] ){	# Assume $attr->{Page} is a page number (counted from 0).
					$this->{Page} = $PDF::PageObjs[ $attr->{Page} ];
				} else {						# Now we have to assume that $attr->{Page} is a Page name.
					$this->{Page} = &PDF::getObjByName( $attr->{Page}) || $PDF::PageObjs[0];	# Finally, if $this->{Page} is still not defined, use the first page.
				}
				push( @{$this->{XML}}, qq{Page="$this->{Page}->{Name}"} );
			}
		};
	} elsif ( $this->{FieldType} eq 'Tx' ){
		if( $type eq 'TextArea' ){
			$this->{Flags} |= $Field::FieldFlags{TextArea};
			$this->{FontSize} ||= 12;
		}
		if( $attr->{MaxLen} ){
			push( @{$this->{XML}}, qq{MaxLen="$attr->{MaxLen}"} );
			$this->{MaxLen} = $attr->{MaxLen};
			if( length( $this->{Value} ) > $attr->{MaxLen} ){
				substr( $this->{Value}, $attr->{MaxLen} ) = '';
			}
		}
		$this->{AP} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
		$this->appendChild( $this->{AP} );
		$this->{AP}->showTextEdit( );
	} elsif ( $type eq 'CheckBox' ){
		if( defined $attr->{Symbol} ){
			push( @{$this->{XML}}, qq{Symbol="$attr->{Symbol}"} );
			$this->{Symbol} = ( $Field::ZaDbSigns{ $attr->{Symbol} } || $attr->{Symbol} );
		}
		$this->{Value} = &PDF::strToName( $this->{Value} );
		$this->{AP} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
		$this->appendChild( $this->{AP} );
		$this->{APDown} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
		$this->appendChild( $this->{APDown} );
		$this->{APChecked} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
		$this->appendChild( $this->{APChecked} );
		$this->{APCheckedDown} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
		$this->appendChild( $this->{APCheckedDown} );
		$this->{APRollOver} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
		$this->appendChild( $this->{APRollOver} );
		$this->{APCheckedRollOver} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
		$this->appendChild( $this->{APCheckedRollOver} );
		if( $PDF::root->getAcroForm( )->{Theme} eq 'WinXP' ){
			$this->{BorderColor} = ( $attr->{BorderColor} || '185284' );
			$this->{BorderWidth} = ( $attr->{BorderWidth} || 2 );
			$this->{FontColor} = ( $attr->{FontColor} || 'Green' );
			for( qw(AP APDown APChecked APCheckedDown APRollOver APCheckedRollOver) ){
				bless $this->{$_}, 'WinXPAppearance';
			}
		}
		$this->{AP}->showCheckBox( 0, 0 );
		$this->{APDown}->showCheckBox( 0, 1 );
		$this->{APChecked}->showCheckBox( 1, 0 );
		$this->{APCheckedDown}->showCheckBox( 1, 1 );
		$this->{APRollOver}->showCheckBox( 0, 2 );
		$this->{APCheckedRollOver}->showCheckBox( 1, 2 );
		if( defined $attr->{Checked} && $attr->{Checked} ){
			$this->{Checked} = 1;
			push( @{$this->{XML}}, qq{Checked="1"} );
		}
	} elsif ( $type eq 'Radio' ){
		if( defined $attr->{Symbol} ){
			push( @{$this->{XML}}, qq{Symbol="$attr->{Symbol}"} );
			$this->{Symbol} = ( $Field::ZaDbSigns{ $attr->{Symbol} } || $attr->{Symbol} );
		}
		$this->{Value} = &PDF::strToName( $this->{Value} );
		if( $Field::RadioButtons{ $this->{FieldName} } ){
			$this->{AP} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
			$this->appendChild( $this->{AP} );
			$this->{APDown} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
			$this->appendChild( $this->{APDown} );
			$this->{APChecked} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
			$this->appendChild( $this->{APChecked} );
			$this->{APCheckedDown} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
			$this->appendChild( $this->{APCheckedDown} );
			$this->{APRollOver} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
			$this->appendChild( $this->{APRollOver} );
			$this->{APCheckedRollOver} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
			$this->appendChild( $this->{APCheckedRollOver} );
			if( $PDF::root->getAcroForm( )->{Theme} eq 'WinXP' ){
				$this->{BorderColor} = ( $attr->{BorderColor} || '185284' );
				$this->{BorderWidth} = ( $attr->{BorderWidth} || 2 );
				$this->{FontColor} = ( $attr->{FontColor} || 'Green' );
				for( qw(AP APDown APChecked APCheckedDown APRollOver APCheckedRollOver) ){
					bless $this->{$_}, 'WinXPAppearance';
				}
			}
			$this->{AP}->showRadio( 0, 0 );
			$this->{APDown}->showRadio( 0, 1 );
			$this->{APChecked}->showRadio( 1, 0 );
			$this->{APCheckedDown}->showRadio( 1, 1 );
			$this->{APRollOver}->showRadio( 0, 2 );
			$this->{APCheckedRollOver}->showRadio( 1, 2 );
			push( @{$Field::RadioButtons{ $this->{FieldName} }->{Kids}}, $this );
			$this->{Parent} = $Field::RadioButtons{ $this->{FieldName} };
			$this->{Parent}->appendChild( $this );
			if( $attr->{Checked} && !defined $this->{Parent}->{DefaultValue} ){
				$this->{Parent}->{DefaultValue} = $this->{Value};
				$this->{Checked} = 1;
				push( @{$this->{XML}}, qq{Checked="1"} );
			}
		} else {
			$Field::RadioButtons{ $this->{FieldName} } = $this;
			new Field( $rect, $type, $attr );
		}
	} elsif ( $this->{FieldType} eq 'Ch' ){
		if( $type eq 'Combo' ){
			$this->{Flags} |= $Field::FieldFlags{Combo};
			if( $attr->{Edit} ){
				$this->{Flags} |= $Field::FieldFlags{Edit};
			}
		}
		if( $attr->{SortBy} || $attr->{Sorted} ){
			$this->{Flags} |= $Field::FieldFlags{Sorted};
			push( @{$this->{XML}}, qq{Sorted="1"} );
			if( $attr->{SortBy} ){
				push( @{$this->{XML}}, qq{SortBy="$attr->{SortBy}"} );
			}
		}
		$this->{Choices} = [ ];
		if( ref( $attr->{Choices} ) eq 'ARRAY' ){
			for( @{$attr->{Choices}} ){		# $this->{Choices} is constructed as an array of array: [ [ entry 1, value 1 ], [ entry 2, value 2 ], ... ]
				if( ref( $_ ) eq 'ARRAY' ){
					push( @{$this->{Choices}}, [ $_->[0], ( defined $_->[1]? $_->[1]: $_->[0] ) ] ) if( defined $_->[0] );
				} else {
					push( @{$this->{Choices}}, [ $_, $_ ] );
				}
			}
		} elsif( ref( $attr->{Choices} ) eq 'HASH' ){
			for( keys %{$attr->{Choices}} ){
				push( @{$this->{Choices}}, [ $_, ( exists $attr->{Choices}->{$_}? $attr->{Choices}->{$_}: $_ ) ] );
			}
		}
		if( $this->{Flags} & $Field::FieldFlags{Sorted} ){
			my $sortby = sub { $a->[0] cmp $b->[0] };
			$attr->{SortBy} ||= '';
			if( $attr->{SortBy} eq 'Z->A' ){
				$sortby = sub { $b->[0] cmp $a->[0] };
				$this->{Flags} ^= $Field::FieldFlags{Sorted};
			} elsif( $attr->{SortBy} eq '0->9' ){
				$sortby = sub { $a->[0] <=> $b->[0] };
				$this->{Flags} ^= $Field::FieldFlags{Sorted};
			} elsif( $attr->{SortBy} eq '9->0' ){
				$sortby = sub { $b->[0] <=> $a->[0] };
				$this->{Flags} ^= $Field::FieldFlags{Sorted};
			}
			@{$this->{Choices}} = sort $sortby @{$this->{Choices}};
		}
		if( defined $attr->{Selected} ){
			$this->{Selected} = $attr->{Selected};		# Must be an index to the array!
			push( @{$this->{XML}}, qq{Selected="$attr->{Selected}"} );
		} else {
			$this->{Selected} = 0;
		}
		$attr->{Selected} ||= 0;
		# If Selected is negative, count backwards, or 0 if too negative. If Selected is too large, use the last element.
		if( $attr->{Selected} < 0 ){
			$this->{Selected} = &PDF::max( 0, scalar @{$this->{Choices}} + $attr->{Selected} );
		} elsif( $attr->{Selected} >= scalar @{$this->{Choices}} ){
			$this->{selected} = scalar @{$this->{Choices}} - 1;
		}
		$this->{Value} = $this->{Choices}->[ $this->{Selected} ]->[1];
		$this->{AP} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
		$this->appendChild( $this->{AP} );
		$this->{AP}->showListBox( );
	}
	# A field should either be registered to the Page object as an Annot but not a child of it -- except for radio button container.
	unless( @{$this->{Kids}} ){
		$this->{PageObj}->appendAnnot( $this, 1 );
	}
	# Radio buttons of a common group won't become children of the AcroForm, but their parent Radio, which is a mere container.
	unless( $this->{Parent} ){
		$PDF::root->getAcroForm( )->appendField( $this );
	}
	return $this;
}

sub commonCode {
	my $this = shift;
	my @strs = map {
		&PDF::escStr( $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{$_} ): $this->{$_} )
	} qw(FieldName Tips);
	if( $this->{DesiredType} ne 'Radio' || @{$this->{Kids}} ){
		print join( $PDF::endln,
			'',
			qq{/FT /$this->{FieldType} },
			qq{/T ($strs[0]) },
			qq{/Ff $this->{Flags} },
			qq{/TU ($strs[1])},
		);
	}
	unless( @{$this->{Kids}} ){
		if( $this->{BorderStyle} || ( $this->{BorderWidth} != 1 ) ){
			print qq{$PDF::endln/BS << /W $this->{BorderWidth} };
			if( $this->{BorderStyle} ne 'N' ){
				print qq{/S /$this->{BorderStyle} };
			}
			if( $this->{BorderDash} ){
				print '/D ' . $this->{AP}->setDash( $this->{BorderDash}, 1 );	# Won't modify stream data of AP; just get the dash array
			}
			print qq{$PDF::endln>> };
		}
		if( $this->{Parent} ){
			print join( $PDF::endln,
				'',
				qq{/Parent $this->{Parent}->{ObjId} 0 R },
			);
		}
	}
	if( @{$this->{Kids}} ){
		print join( $PDF::endln,
			'',
			'/Kids [ ' . join( ' ', map{ "$_->{ObjId} 0 R" } @{$this->{Kids}} ) . ' ] ',
		);
	}
}

sub makeMK {
	my $this = shift;
	print join( $PDF::endln,
		'',
		'/MK << ',
		join( ' ', '/BC [', &Color::tellColor( $this->{BorderColor} ), '] ' ),
		join( ' ', '/BG [', &Color::tellColor( $this->{BgColor} ), '] ' ),
	);
	if( $this->{DesiredType} eq 'Button' ){
		my $str = &PDF::escStr( $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{Caption} ): $this->{Caption} );
		print qq{$PDF::endln/CA ($str) };
	}
	print qq{$PDF::endln>> };
}

sub btnCode {
	my $this = shift;
	$this->commonCode( );
	my @strs = map {
		&PDF::escStr( $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{$_} ): $this->{$_} )
	} qw(DefaultApp Url File JS);
	print join( $PDF::endln,
		'',
		qq{/H /$this->{Highlight} },
		qq{/DA ($strs[0]) },
		'/AP <<',
		qq{/N $this->{AP}->{ObjId} 0 R },
		qq{/R $this->{APRollOver}->{ObjId} 0 R },
	);
	if( $this->{APDown} ){
		print qq{/D $this->{APDown}->{ObjId} 0 R };
	}
	print '>> ';
	$this->makeMK( );
	if( $this->{Action} eq 'Submit' ){
		my $flag = 4;
		for( qw(Get Coord XFDF Annots AsPDF) ){
			next if( !defined $this->{$_} );
			$flag += $Field::SubmitFlags{ $_ };
		}
		if( $this->{FDF} || $this->{XFDF} || $this->{AsPDF} ){
			$flag ^= 4;
		}
		print  qq{$PDF::endln/A << /S /SubmitForm /F << /FS /URL /F ($strs[1]) >> /Flags $flag >> };
	} elsif( $this->{Action} eq 'Reset' ){
		print qq{$PDF::endln/A << /S /ResetForm >> };
	} elsif( $this->{Action} eq 'SendMail' ){
		print qq{$PDF::endln/A << /S /Named /N /AcroSendMail:SendMail >> };
	} elsif( $this->{Action} eq 'FlipPage' ){
		print qq{$PDF::endln/A << /S /Named /N /$this->{Dest} >> };
	} elsif( $this->{Action} eq 'Print' ){
		print qq{$PDF::endln/A << /S /Named /N /Print >> };
	} elsif( $this->{Action} eq 'Goto' ){
		print $this->{File}?
			qq{$PDF::endln/A << /S /GoToR /F ($strs[2]) /D [ $this->{Page} /Fit ] >> }:
			qq{$PDF::endln/A << /S /GoTo /D [ $this->{Page}->{ObjId} 0 R /Fit ] >> };
	} elsif( $this->{Action} eq 'JS' ){
		print $PDF::endln . qq{/A << /S /JavaScript /JS ($strs[3]) >> };
	}
}

sub txCode {
	my $this = shift;
	$this->commonCode( );
	my @strs = map {
		&PDF::escStr( $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{$_} ): $this->{$_} )
	} qw(Value DefaultApp);
	print join( $PDF::endln,
		'',
		qq{/DV ($strs[0]) },
		qq{/V ($strs[0]) },
		qq{/DA ($strs[1])},
		qq{/AP << /N $this->{AP}->{ObjId} 0 R >> },
		'/MK << ',
		join( ' ', '/BC [', &Color::tellColor( $this->{BorderColor} ), '] ' ),
		join( ' ', '/BG [', &Color::tellColor( $this->{BgColor} ), '] ' ),
		'>> ',
	);
	if( $this->{MaxLen} ){
		print $PDF::endln . qq{/MaxLen $this->{MaxLen} };
	}
}

sub checkCode {
	my $this = shift;
	$this->commonCode( );
	if( $this->{DesiredType} eq 'Radio' && @{$this->{Kids}} ){
		if( defined $this->{DefaultValue} ){
			print qq{/V /$this->{DefaultValue} $GraphContent::endln};
		}
	} else {
		my $str = &PDF::escStr( $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{DefaultApp} ): $this->{DefaultApp} );
		print join( $PDF::endln,
			'',
			'/H /T',
			qq{/DA ($str)},
			'/AP <<',
			qq{/N << /Off $this->{AP}->{ObjId} 0 R /$this->{Value} $this->{APChecked}->{ObjId} 0 R >> },
			qq{/D << /Off $this->{APDown}->{ObjId} 0 R /$this->{Value} $this->{APCheckedDown}->{ObjId} 0 R >> },
			qq{/R << /Off $this->{APRollOver}->{ObjId} 0 R /$this->{Value} $this->{APCheckedRollOver}->{ObjId} 0 R >> },
			'>>'
		);
		my $v = ( $this->{Checked}? $this->{Value}: 'Off' );
		print qq{$PDF::endln/V /$v };
		print qq{$PDF::endln/AS /$v };
	}
}

sub chCode {
	my $this = shift;
	$this->commonCode( );
	my @strs = map {
		&PDF::escStr( $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{$_} ): $this->{$_} )
	} qw(Value DefaultApp);
	my @strs1 = &PDF::escStr( map { $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $_->[0] ): $_->[0] } @{$this->{Choices}} );
	my @strs2 = &PDF::escStr( map { my $s = defined $_->[1]? $_->[1]: $_->[0];
		$PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $s ): $s;
	} @{$this->{Choices}} );
	$this->makeMK( );
	print join( $PDF::endln,
		'',
		qq{/V ($strs[0])},
		qq{/DV ($strs[0])},
		qq{/DA ($strs[1])},
		qq{/AP << /N $this->{AP}->{ObjId} 0 R >> },
		'/Opt [ ',
		( map{ qq{[($strs2[$_])($strs1[$_])] }; } 0..$#{$this->{Choices}} ),
		'] ',
	);
}

sub startXML {
	my( $this, $dep ) = @_;
	if( $this->{DesiredType} eq 'Radio' ){
		@{$this->{Kids}} && return;
		ref( $this->{par} ) eq 'Field' || ++$dep;
	} else {
		$dep++;
	}
	# This is because the exportXML function reduced the depth value by 2 because document-level objects do not produce XML tags, except for AcroForm
	# However, radio buttons that forming a group has a common parent that is also a radio button but would NOT produce any XML code.
	# If a radio button is standalone, it should be indented like other fields.
	print "\t" x $dep, '<', ref( $this ),
		' Type="', $this->{DesiredType}, '"',
		' Name="', &PDF::escXMLChar( $this->{FieldName} ), '"',
		' OnPage="', &PDF::escXMLChar( $this->{PageObj}->{Name} ), '"';
	print ' Rect="', join( ', ', $this->{rect}->{Left}, $this->{rect}->{Bottom}, $this->{rect}->{Right}, $this->{rect}->{Top} ), '"';
	print join( ' ', '', @{$this->{XML}} );
	if( $this->{FieldType} eq 'Ch' ){
		print ">\n";
	} elsif( $this->{DesiredType} eq 'TextArea' ){
		print ">", &PDF::escXMLChar( $this->{Value} );
	} else {
		print " />\n";
	}
	if( $this->{FieldType} eq 'Ch' ){
		map { print "\t" x ( $dep + 1 ), '<Option Value="', &PDF::escXMLChar( $_->[1] ), '">', &PDF::escXMLChar( $_->[0] ), qq{</Option>\n}; } @{$this->{Choices}};
	}
}

sub endXML {
	my( $this, $dep ) = @_;
	if( $this->{DesiredType} eq 'TextArea' || $this->{FieldType} eq 'Ch' ){
		print "\t" x ( $dep + 1 ) if ( $this->{FieldType} eq 'Ch' );
		print '</', ref( $this ), ">\n";
	}
}

sub newFromXML {
	my( $class, $xml ) = @_;
	my @rectsides = split( /,\s*/, $xml->{Rect} );
	if( $xml->{Type} eq 'TextArea' ){
		$xml->{Value} = join( '', map{ $_->{Text} } @{$xml->{Kids}} );
		@{$xml->{Kids}} = ( );
	} elsif( $Field::AbbrNames{ $xml->{Type} } eq 'Ch' ){
		$xml->{Choices} = [ ];
		for my $kid ( @{$xml->{Kids}} ){
			if( ref( $kid ) =~ /::Option$/ ){
				my $text = join( '', map{ $_->{Text} } @{$kid->{Kids}} );
				$text =~ s/(^\s+)|(\s+$)//g;
				push( @{$xml->{Choices}}, [ $text, $kid->{Value} ] );
			}
		}
		@{$xml->{Kids}} = ( );
	}
	bless $xml, 'HASH';
	return new Field( new Rect( @rectsides ), $xml->{Type}, $xml );
}

sub finalize {
	my $this = shift;
	$this->SUPER::finalize( );
	for( qw(AP APDown Icon Page Parent APChecked APCheckedDown Choices PageObj Kids Font) ){
		delete $this->{$_};
	}
	if( exists $Field::RadioButtons{ $this->{FieldName} } ){
		delete $Field::RadioButtons{ $this->{FieldName} };
	}
}

1;
