#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package Outlines;

use PDFTreeNode;

@ISA = qw(PDFTreeNode);

sub new {
	my( $class, $title, $attr ) = @_;
	my $this = {
		'Count' => 0,
		'Title' => $title,
		'Dest' => undef,	# Page object
		'Fit' => 'Fit',		# Fit method
		'Name' => '',
		'XML' => [ ],
		'Color' => '',		# New for Acrobat 5.0
		'Flag' => 0,		# New for Acrobat 5.0
		'PObject' => undef,	# New for v3.0 for importing bookmarks from PDFFile
	};
	bless $this, $class;
	if( $PDF::root->{Catalog}->{Outlines} ){
		# If destination page is defined, set Dest to that page.
		if( ref $attr eq 'HASH' && defined $attr->{Page} ){	# $attr->{Page} is the Name of the Page or a Page object
			if( ref( $attr->{Page} ) eq 'Page' ){
				$this->{Dest} = $attr->{Page};
			} elsif( $attr->{Page} =~ /^\d+$/  ){
				$this->{Dest} = $PDF::root->getPagesRoot( )->getPageByNumber( $attr->{Page} );
			} else {
				$this->{Dest} = $PDF::root->getObjByName( $attr->{Page} );
			}
		}
		# If destination page is not defined or not found, set Dest to current page.
		unless( defined $this->{Dest} ){
			$this->{Dest} = $PDF::root->{CurrPage};
		}
		if( ref $attr eq 'HASH' && defined $attr->{Fit} ){
			# other keys in %$attr needed: Left, Top, Bottom, Right, Zoom
			for( qw(Left Top Bottom Right Zoom) ){
				next unless( defined $attr->{$_} );
				push( @{$this->{XML}}, qq{$_="$attr->{$_}"} );
				$attr->{$_} = &PDF::tellSize( $attr->{$_} );
			}
			if( $attr->{Fit} eq 'FitH' ){
				$this->{Fit} = qq{FitH $attr->{Top}};
			} elsif( $attr->{Fit} eq 'FitV' ){
				$this->{Fit} = qq{FitH $attr->{Left}};
			} elsif( $attr->{Fit} eq 'FitR' ){
				$this->{Fit} = qq{FitR $attr->{Left} $attr->{Bottom} $attr->{Right} $attr->{Top}};
			} elsif( $attr->{Fit} eq 'XYZ' ){
				$this->{Fit} = qq{XYZ $attr->{Left} $attr->{Top} $attr->{Zoom}};
			}
		}
		$this->{Title} ||= '(Untitled)';
		if( ref $attr eq 'HASH' ){
			if( defined $attr->{Bold} && $attr->{Bold} ){
				$this->{Flag} |= 2;
				push( @{$this->{XML}}, qq{Bold="1"} );
			}
			if( defined $attr->{Italic} && $attr->{Italic} ){
				$this->{Flag} |= 1;
				push( @{$this->{XML}}, qq{Italic="1"} );
			}
			if( defined $attr->{Color} ){
				$this->{Color} = $attr->{Color};
				push( @{$this->{XML}}, qq{Color="$this->{Color}"} );
			}
			# If parent Outlines node is defined and valid, append this node to parent.
			if( defined $attr->{Parent} ){
				my $bk = ref( $attr->{Parent} ) eq $class? $attr->{Parent}: &PDF::getObjByName( $attr->{Parent} );
				$bk->appendEntry( $this ) if( $bk && ref( $bk ) eq $class );
			}
		}
		if( ref $attr eq 'HASH' && exists $attr->{Name} ){
			$this->setName( $attr->{Name} );
		} else {
			$this->setName( );
		}
		# If parent is not defined, append this node to root of Outlines tree.
		unless( $this->{par} ){
			$PDF::root->{Catalog}->{Outlines}->appendEntry( $this );
		}
	} else {
		$PDF::root->{Catalog}->appendOutlines( $this );
		$this->{Title} = $PDF::root->{Catalog}->{DocInfo}->{Title};
	}
	if( ref( $attr ) eq 'PObject' ){
		$this->{PObject} = $attr;
		$this->{PObject}->{Data}->{Parent} = $this->{par};
		$this->{PObject}->{Data}->{Title} = bless [ $this->{Title} ], 'PCharStr';
	}
	return $this;
}

sub appendEntry {
	my( $this, $entry ) = @_;
	return unless( ref( $this ) eq ref( $entry ) );
	my $ptr;
	if( defined $entry->{par} ){
		$ptr = $entry->{par};
		$entry->{par}->deleteChild( $entry );
		do {
			$ptr->{Count}--;
			$ptr = $ptr->{par};
		} while( $ptr != $PDF::root->{Catalog} );
	}
	$entry->{par} = undef;
	$this->appendChild( $entry );
	$ptr = $this;
	do {
		$ptr->{Count}++;
		$ptr = $ptr->{par};
	} while( $ptr && ref( $ptr ) eq ref( $this ) );
	return $entry;
}

%AppendMethods = (
	Outlines => \&appendEntry,
);

sub add {
	my( $this, $that ) = @_;
	if( defined $AppendMethods{ ref( $that ) } ){
		&{$AppendMethods{ ref( $that ) }}( $this, $that );
	}
	return $that;
}

sub getObjId {
	my $this = shift;
	if( $this->{PObject} ){
		return $this->{PObject}->{ObjId};
	} else {
		return $this->{ObjId};
	}
}

sub makeCode {
	my $this = shift;
	if( $this->{PObject} ){
		if( $this->{next} ){
			$this->{PObject}->{Data}->{Next} = (
				$this->{next}->{PObject}? $this->{next}->{PObject}: $this->{next}
			);
		}
		if( $this->{prev} ){
			$this->{PObject}->{Data}->{Prev} = (
				$this->{prev}->{PObject}? $this->{prev}->{PObject}: $this->{prev}
			);
		}
		$this->{PObject}->{Data}->{Parent} = $this->{par};
		return;
	}
	print join( $PDF::endln,
		qq{$this->{ObjId} 0 obj},
		'<< ',
		qq{/Count $this->{Count} },
	);
	if( $this->{Count} ){
		print join( $PDF::endln,
			'',
			sprintf( "/First %d 0 R", $this->{son}->getObjId( ) ),
			sprintf( "/Last %d 0 R", $this->{last}->getObjId( ) ),
		);
	}
	if( $this->{Dest} ){
		print join( $PDF::endln,
			'',
			sprintf( '/Title (%s)', &PDF::escStr( $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{Title} ): $this->{Title} ) ),
			sprintf( '/Dest [ %d 0 R /%s ]', $this->{Dest}->getObjId( ), $this->{Fit} ),
			qq{/Parent $this->{par}->{ObjId} 0 R },
		);
		if( $this->{next} ){
			printf( "$PDF::endln/Next %d 0 R ", $this->{next}->getObjId( ) );
		}
		if( $this->{prev} ){
			printf( "$PDF::endln/Prev %d 0 R ", $this->{prev}->getObjId( ) );
		}
	}
	if( $this->{Color} ){
		print join( ' ', qq{$PDF::endln/C [}, &PDF::tellColor( $this->{Color}, 'RGB' ), ']' );
	}
	if( $this->{Flag} ){
		print qq{$PDF::endln/F $this->{Flag}};
	}
	print join( $PDF::endln,
		'',
		'>> ',
		'endobj',
		''
	);
}

# This function is NOT a class-specific method
sub decToRoman {
	my $k = ( shift ) % 4000;	# Must be smaller than 4000
	my $roman = '';
	my $romanchars = [ [ qw(I II III IV V VI VII VIII IX) ], [ qw(X XX XXX XL L LX LXX LXXX XC) ], [ qw(C CC CCC CD D DC DCC DCCC CM) ], [ qw(M MM MMM) ] ];
	my $i = 0;
	while( $k ){
		if( $k%10 ){ $roman = $romanchars->[$i]->[$k%10-1] . $roman; }
		$k = int( $k / 10 ); $i++;
	}
	return $roman;
}

# Number all sub-entries (not recursively). Keys may be defined in %$attr: Style, Start
sub numbering {
	my( $this, $attr ) = @_;
	my $num = ( $attr->{Start} || 1 );
	if( $attr->{Style} eq 'A' ){
		$num = [ 'A'..'Z' ]->[ ($num - 1) % 26 ];
	} elsif( $attr->{Style} eq 'a' ){
		$num = [ 'a'..'z' ]->[ ($num - 1) % 26 ];
	}
	my $ptr = $this->{son};
	return if( !$ptr );
	while( $ptr ){
		my $str = $num;
		if( $attr->{Style} eq 'I' ){
			$str = &decToRoman( $num );
		} elsif( $attr->{Style} eq 'i' ){
			$str = lc( &decToRoman( $num ) );
		}
		$ptr->{Title} = join( '', $str, ". ", $ptr->{Title} );
		$ptr = $ptr->{next};
		$num++;
	}	
}

sub startXML {
	my( $this, $dep ) = @_;
	return if( $this->{par} == $PDF::root->{Catalog} );
	print "\t" x $dep, "<", ref( $this );
	my $title = &PDF::escXMLChar( $this->{Title} );
	print qq{ Title="$title" Page="$this->{Dest}->{Name}" Name="$this->{Name}"};
	if( ref( $this->{par} ) eq ref( $this ) && $this->{par} != $PDF::root->{Catalog}->{Outlines} ){
		print qq{ Parent="$this->{par}->{Name}"};
	}
	print join( ' ', '', @{$this->{XML}} );
	print $this->{son}? ">\n": " />\n";
}

sub endXML {
	my( $this, $dep ) = @_;
	if( $this->{son} && $this->{par} != $PDF::root->{Catalog} ){
		print "\t" x $dep, "</", ref( $this ), ">\n";
	}
}

sub newFromXML {
	my( $class, $xml ) = @_;
	bless $xml, 'HASH';
	return new Outlines( $xml->{Title}, $xml );
}

sub finalize {
	my $this = shift;
	for( qw(Parent Page Dest PObject) ){
		undef $this->{$_};
	}
}

1;
