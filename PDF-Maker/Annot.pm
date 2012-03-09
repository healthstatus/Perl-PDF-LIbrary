#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package EmbeddedFile;

use Carp;

@ISA = qw(PDFStream);

%EmbeddedFile::ContentTypes = (
	'aiff'	=> 'audio/x-aiff',
	'au'	=> 'audio/basic',
	'avi'	=> 'video/avi',
	'bmp'	=> 'image/bmp',
	'css'	=> 'text/css',
	'doc'	=> 'application/msword',
	'dwg'	=> 'application/acad',
	'dwf'	=> 'drawing/x-dwf',
	'dxf'	=> 'application/dxf',
	'eps'	=> 'application/postscript',
	'fdf'	=> 'application/vnd.fdf',
	'fh'	=> 'image/x-freehand',
	'gif'	=> 'image/gif',
	'gz'	=> 'application/x-gzip',
	'hqx'	=> 'application/mac-binhex40',
	'hta'	=> 'application/hta',
	'htm'	=> 'text/html',
	'html'	=> 'text/html',
	'ico'	=> 'image/x-icon',
	'jpeg'	=> 'image/jpeg',
	'jpg'	=> 'image/jpeg',
	'js'	=> 'application/x-javascript',
	'm3u'	=> 'audio/x-mpegurl',
	'mdb'	=> 'application/msaccess',
	'mid'	=> 'audio/midi',
	'mov'	=> 'video/quicktime',
	'mp3'	=> 'audio/x-mpeg',
	'mpe'	=> 'video/mpeg',
	'mpeg'	=> 'video/mpeg',
	'mpg'	=> 'video/mpeg',
	'pbm'	=> 'image/portable-bitmap',
	'pdf'	=> 'application/pdf',
	'pgm'	=> 'image/portable-graymap',
	'pic'	=> 'image/pict',
	'pict'	=> 'image/pict',
	'png'	=> 'image/png',
	'pnm'	=> 'image/portable-anymap',
	'ppm'	=> 'image/portable-pixmap',
	'ppt'	=> 'application/vnd.ms-powerpoint',
	'ps'	=> 'application/postscript',
	'qt'	=> 'video/quicktime',
	'ra'	=> 'audio/x-pn-realaudio',
	'ram'	=> 'audio/x-pn-realaudio',
	'rgb'	=> 'image/rgb',
	'rm'	=> 'audio/x-pn-realaudio',
	'rtf'	=> 'application/rtf',
	'shtml'	=> 'text/x-server-parsed-html',
	'snd'	=> 'audio/basic',
	'swf'	=> 'application/x-shockwave-flash',
	'tar'	=> 'application/x-tar',
	'tex'	=> 'application/x-tex',
	'text'	=> 'text/plain',
	'tgz'	=> 'application/x-compressed',
	'tif'	=> 'image/tiff',
	'tiff'	=> 'image/tiff',
	'txt'	=> 'text/plain',
	'uin'	=> 'application/x-icq',
	'vrml'	=> 'x-world/x-vrml',
	'wav'	=> 'audio/wav',
	'xls'	=> 'application/vnd.ms-excel',
	'xml'	=> 'text/xml',
	'xsl'	=> 'text/xsl',
	'z'		=> 'application/x-compress',
	'zip'	=> 'application/x-zip-compressed',
);

sub new {
	my( $class, $file, $attr ) = @_;
	my $this = new PDFStream;
	$this->{Size} = 0;
	$this->{MimeType} = $attr->{MimeType};
	my $buffer = '';
	my $len = 0;
	$this->{File} = &PDF::secureFileName( $file );
	my $fh = new FileHandle( "<$this->{File}" );
	if( !defined $fh ){ croak "Can't open file $file."; }
	binmode( $fh );
	while( $len = read( $fh, $buffer, 4000 ) ){
		$this->{Stream} .= $buffer;
		$this->{Size} += $len;
	}
	close( $fh );
	if( $attr->{CheckSum} ){
		$this->{CheckSum} = &PDF::MD5( $this->{Stream} );
	}
	$file =~ m/([^\.]+)$/;
	my $ext = lc( $1 );
	if( !$this->{MimeType} && $EmbeddedFile::ContentTypes{ $ext } ){
		$this->{MimeType} = $EmbeddedFile::ContentTypes{ $ext };
	}
	bless $this, $class;
}

sub customCode {
	my $this = shift;
	print join( $PDF::endln,
		'',
		'/Type /EmbeddedFile ',
	);
	if( $this->{MimeType} ){
		my $str = &PDF::escStr( $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{MimeType} ): $this->{MimeType} );
		print qq{$PDF::endln /Subtype ($str) };
	}
	print qq{$PDF::endln/Params << /Size $this->{Size} };
	if( $this->{CheckSum} ){
		print $PDF::endln, '/Checksum <', unpack( 'H*', $this->{CheckSum} ), '> ';
	}
	print qq{>>$PDF::endln};
}

##############################################################################

package Annot;

use Shape;
use Appearance;

@ISA = qw(PDFTreeNode);

%Annot::AnnotFlags = (
	'Invisible' => 1,
	'Hidden' => 2,
	'NoZoom' => 8,
	'NoRotate' => 16,
	'NoView' => 32,
	'ReadOnly' => 64,
);

%Annot::StampCaptions = (
	'Approved' => 'APPROVED',
	'AsIs' => 'AS IS',
	'Confidential' => 'CONFIDENTIAL',
	'Departmental' => 'DEPARTMENTAL',
	'Draft' => 'DRAFT',
	'Experimental' => 'EXPERIMENTAL',
	'Expired' => 'EXPIRED',
	'Final' => 'FINAL',
	'ForComment' => 'FOR COMMENT',
	'ForPublicRelease' => "FOR PUBLIC\nRELEASE",
	'NotApproved' => 'NOT APPROVED',
	'NotForPublicRelease' => "NOT FOR PUBLIC\nRELEASE",
	'Sold' => 'SOLD',
	'TopSecret' => 'TOPSECRET',
);

sub new {
	my( $class, $rect, $subtype, $attr ) = @_;
	my $this = {
		'rect' => $rect,
		'Subtype' => $subtype,
		'URI' => undef,
		'IconName' => undef,
		'Color' => '',
		'AP' => undef,
		'Flag' => 4,
		'Popup' => undef,
		'PageObj' => $PDF::root->{CurrPage},
		'Parent' => undef,
		'Open' => 'false',
		'Contents' => undef,
		'ModTime' => &PDF::tellTime( ),
		'Dir' => 0,
		'XML' => [ ],
		'Auto' => ( defined $attr->{Auto}? 1: 0 ),	# Created internally?
		'Opacity' => 1,
	};
	bless $this, $class;
	if( defined $attr->{Color} ){
		$this->{Color} = $attr->{Color};
		push( @{$this->{XML}}, qq{Color="$attr->{Color}"} );
	}
	if( defined $attr->{OnPage} ){
		if( ref( $attr->{OnPage} ) eq 'Page' ){			# In this case, $attr->{OnPage} is a Page object.
			$this->{PageObj} = $attr->{OnPage};
		} elsif( $attr->{OnPage} =~ /^\d+$/ && $PDF::PageObjs[ $attr->{OnPage} ] ){	# Assume $attr->{OnPage} is a page number (counted from 0).
			$this->{PageObj} = $PDF::PageObjs[ $attr->{OnPage} ];
		} else {										# Now we have to assume that $attr->{OnPage} is a Page name.
			$this->{PageObj} = &PDF::getObjByName( $attr->{OnPage} ) || $PDF::root->{CurrPage};
		}
	}
	for( keys %Annot::AnnotFlags ){
		if( $attr->{$_} ){
			$this->{Flag} |= $Annot::AnnotFlags{$_};
			push( @{$this->{XML}}, qq{$_="1"} );
		}
	}
	if( $attr->{NoPrint} ){
		$this->{Flag} ^= 4;
		push( @{$this->{XML}}, qq{NoPrint="1"} );
	}
	if( $attr->{Contents} && { 'Text'=>1, 'FileAttachment'=>1, 'Stamp'=>1 }->{ $subtype } ){
		$this->{Contents} = $attr->{Contents};
		$this->{Title} = ( $attr->{Title} || $PDF::root->{DocInfo}->{Author} );
		push( @{$this->{XML}}, qq{Contents="} . &PDF::escXMLChar( $attr->{Contents} ) . '"' );
		push( @{$this->{XML}}, qq{Title="} . &PDF::escXMLChar( $attr->{Title} ) . '"' );
		if( $attr->{Open} ){
			push( @{$this->{XML}}, qq{Open="1"} );
		}
		unless( ref( $attr->{PopupRect} ) eq 'Rect' ){
			$attr->{PopupRect} = new Rect( $rect->{Left}, $rect->{Bottom} - 40 );
			$attr->{PopupRect}->width( 120 );
			$attr->{PopupRect}->height( 40 );
		}
		push( @{$this->{XML}}, qq{PopupRect="} . join( ', ', $attr->{PopupRect}->{Left}, $attr->{PopupRect}->{Bottom}, $attr->{PopupRect}->{Right}, $attr->{PopupRect}->{Top} ) . '"' );
		$this->{Popup} = new Annot( $attr->{PopupRect}, 'Popup', { 'Auto'=> 1, 'Open'=>$attr->{Open}, 'NoZoom'=>1, 'NoPrint'=>1, 'NoRotate'=>1 } );
		$this->{Popup}->{Parent} = $this;
	}
	if( $subtype eq 'Link' ){
		for( qw(URI Width Dash Border) ){
			next unless( defined $attr->{$_} );
			$this->{$_} = $attr->{$_};
			push( @{$this->{XML}}, qq{$_="$attr->{$_}"} );
		}
		unless( $attr->{Dash} ){
			$this->{Dash} = 'Dotted';
		}
		unless( !defined $attr->{Border} || $attr->{Border} eq 'None' ){
			$this->{Width} ||= '0.5';
		}
		$this->{Width} ||= 0;
		$this->{Highlight} = { qw(Push P Invert I None N Outline O) }->{ $attr->{Highlight} || 'Invert' };
		$this->{Highlight} ||= 'I';
	} elsif( $subtype eq 'Stamp' ){
		# Must be: Approved AsIs Confidential Departmental Draft Experimental Expired Final ForComment ForPublicRelease NotApproved NotForPublicRelease Sold TopSecret
		$this->{IconName} = ( $attr->{IconName} || 'Draft' );
		push( @{$this->{XML}}, qq{IconName="} . &PDF::escXMLChar( $attr->{IconName} ) . '"' );
		for( qw(FontFace SkewAngle SkewDir UseAdobeIcon) ){
			next unless( defined $attr->{$_} );
			$this->{$_} = $attr->{$_};
			push( @{$this->{XML}}, qq{$_="$attr->{$_}"} );
		}
		if( !exists $PDF::Fonts{ $this->{FontFace} } ){
			$this->{FontFace} = 'Helvetica';
		}
		$this->{Color} ||= 'Red';
		unless( $attr->{UseAdobeIcon} ){
			$this->{AP} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
			$this->appendChild( $this->{AP} );
			$this->{AP}->showStamp( $Annot::StampCaptions{$this->{IconName}} || $this->{IconName} );
			$this->{IconName} = &PDF::strToName( $this->{IconName} );
		}
	} elsif( $subtype eq 'Text' ){
		$this->{IconName} = ( $attr->{IconName} || 'Note' );	# Must be: Comment Key Note Help NewParagraph Paragraph Insert
		for( qw(IconName UseAdobeIcon) ){
			next unless( defined $attr->{$_} );
			$this->{$_} = $attr->{$_};
			push( @{$this->{XML}}, qq{$_="$attr->{$_}"} );
		}
		my $icon = $Appearance::AnnotIcons{ $attr->{IconName} };
		if( !$icon ){
			$icon = $Appearance::AnnotIcons{ 'Note' };
			$this->{IconName} = 'Note';
		}
		$rect->width( $icon->[0] );		# Icon is smaller than 32 x 32 fixed size
		$rect->height( $icon->[1] );
		$this->{Color} ||= 'Yellow';
		$this->{Flag} |= 0x18;	# 8 (No zoom) + 16 (No rotate)
		unless( $attr->{UseAdobeIcon} ){
			$this->{AP} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
			$this->appendChild( $this->{AP} );
			$this->{AP}->showIcon( $this->{IconName} );
		}
	} elsif( $subtype eq 'Popup' ){
		$this->{Open} = ( $attr->{Open}? 'true': 'false' );
		push( @{$this->{XML}}, qq{Popup="$attr->{Open}"} ) if( defined $attr->{Open} );
	} elsif( { qw(StrikeOut 1 Underline 1 Highlight 1) }->{$subtype} ){
		$this->{AP} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
		for( qw(Width Dash) ){
			next unless( defined $attr->{$_} );
			$this->{$_} = $attr->{$_};
			push( @{$this->{XML}}, qq{$_="$attr->{$_}"} );
		}
		$this->appendChild( $this->{AP} );
		if( $subtype eq 'Highlight' ){
			$this->{Color} ||= 'Yellow';
		}
		$this->{Subtype} eq 'StrikeOut' && $this->{AP}->showStrikeOut( $this->{Color}, $this->{Width}, $this->{Dash} );
		$this->{Subtype} eq 'Highlight' && $this->{AP}->showHighlight( $this->{Color}, $this->{Width}, $this->{Dash} );
		$this->{Subtype} eq 'Underline' && $this->{AP}->showUnderline( $this->{Color}, $this->{Width}, $this->{Dash} );
	} elsif( $subtype eq 'FileAttachment' ){
		for( qw(IconName File UseAdobeIcon) ){
			next unless( defined $attr->{$_} );
			# Just store them into XML; the attributes will be constructed below.
			push( @{$this->{XML}}, qq{$_="$attr->{$_}"} );
		}
		$this->{IconName} = ( $attr->{IconName} || 'PushPin' );	# Must be: PushPin Graph Paperclip Tag
		my $icon = $Appearance::AnnotIcons{ $attr->{IconName} };
		if( !$icon ){
			$icon = $Appearance::AnnotIcons{ 'PushPin' };
			$this->{IconName} = 'PushPin';
		}
		$rect->width( $icon->[0] );		# Icon is smaller than 32 x 32 fixed size
		$rect->height( $icon->[1] );
		$this->{Color} ||= 'Blue';
		$this->{FileObj} = new EmbeddedFile( $attr->{File}, $attr );
		$this->appendChild( $this->{FileObj} );
		$this->{Flag} |= 0x18;	# 8 (No zoom) + 16 (No rotate)
		$attr->{File} =~ m/([^\\\/\:]+)$/;
		$this->{File} = $1;
		unless( $attr->{UseAdobeIcon} ){
			$this->{AP} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
			$this->appendChild( $this->{AP} );
			$this->{AP}->showIcon( $this->{IconName} );
		}
	} elsif( $subtype eq 'Line' ){
		$this->{Width} = ( $attr->{Width} || 1 );
		push( @{$this->{XML}}, qq{Width="$attr->{Width}"} ) if( defined $attr->{Width} );
	# FreeText annotation added 10/07/2002
	} elsif( $subtype eq 'FreeText' ){
		$this->{Contents} = $attr->{Contents};
		$this->{Title} = ( $attr->{Title} || $PDF::root->{DocInfo}->{Author} );
		for( qw(Contents Title BgColor Color BorderWidth FontFace FontSize) ){
			next unless( defined $attr->{$_} );
			push( @{$this->{XML}}, qq{$_="$attr->{$_}"} );
		}
		if( exists $attr->{BgColor} && $attr->{BgColor} ne '' ){	# Non-transparent background color
			$this->{Color} = $attr->{BgColor};	# /C sets *background* color!
		} else {
			delete $this->{Color};
		}
		if( exists $attr->{Color} ){
			$this->{FontColor} = $attr->{Color};
		}
		$this->{BorderWidth} = ( exists $attr->{BorderWidth} && $attr->{BorderWidth}> 0? $attr->{BorderWidth}: 0 );
		$this->{FontFace} = ( $attr->{FontFace} || 'Helvetica' );
		$this->{FontSize} = ( exists $attr->{FontSize} && $attr->{FontSize}> 0? $attr->{FontSize}: 10 );
		if( exists $attr->{Align} ){
			$this->{Align} = $attr->{Align};
			push( @{$this->{XML}}, qq{Align="$attr->{Align}"} );
		}
		if( exists $attr->{Rotate} ){
			$this->{Rotate} = $attr->{Rotate};
			push( @{$this->{XML}}, qq{Rotate="$attr->{Rotate}"} );
		}
		$this->{AP} = new Appearance( new Rect( 0, 0, $rect->width( ), $rect->height( ) ) );
		$this->appendChild( $this->{AP} );
		$this->{AP}->showFreeText( );
	} elsif( $subtype ne 'Widget' ){
		&PDF::PDFError( $class, "Unknown subtype of annotation $subtype." );
	}
	if( $attr->{Opacity} ){	# For Acrobat 5
		$this->{Opacity} = $attr->{Opacity};
		push( @{$this->{XML}}, qq{Opacity="$attr->{Opacity}"} );
	}
	# AcroForm Fields (Widgets) are special. They will determine themselves whether or not to be considered an Annot.
	$this->{PageObj}->appendAnnot( $this ) unless( $subtype eq 'Widget' );
	return $this;
}

sub adjustStartPos {
	my( $this, $offx, $offy ) = @_;
	$this->{rect}->{Left} += $offx;
	$this->{rect}->{Right} += $offx;
	$this->{rect}->{Top} += $offy;
	$this->{rect}->{Bottom} += $offy;
}

sub flip {
	my( $this, $refrect, $dir ) = @_;	# Dir = 1, 2, 3 corresponding to text direction
	return if( !$dir );
	my $r = $this->{rect};
	my $dy = $refrect->top( ) - $r->top( );
	my $dx = $r->left( ) - $refrect->left( );
	my $w = $r->width( );
	my $h = $r->height( );
	if( $dir == 1 ){
		$r->moveBy( $dy - $dx, $dy + $dx + $h );
	} elsif( $dir == 2 ){
		$r->moveBy( 0 - $dx - $dy - $h, $dy + $h - $dx - $w );
	} elsif( $dir == 3 ){
		$r->moveBy( 0 - 2 * $dx - $w, $dy * 2 + $h );
	}
	unless( $dir == 3 ){
		$this->{rect}->width( $h );
		$this->{rect}->height( $w );
	}
	$this->{Dir} = $dir;
	$this->{AP}->{Stream} = '';
	$this->{Subtype} eq 'StrikeOut' && $this->{AP}->showStrikeOut( $this->{Color}, $this->{Width}, $this->{Dash} );
	$this->{Subtype} eq 'Highlight' && $this->{AP}->showHighlight( $this->{Color}, $this->{Width}, $this->{Dash} );
	$this->{Subtype} eq 'Underline' && $this->{AP}->showUnderline( $this->{Color}, $this->{Width}, $this->{Dash} );
}

sub makeCode {
	my $this = shift;
	my $rect = $this->{rect};
	print join( $PDF::endln,
		qq{$this->{ObjId} 0 obj},
		'<< ',
	);
	unless( defined $this->{Kid} && @{$this->{Kids}} ){
		print join( $PDF::endln,
			'',
			'/Type /Annot',
			qq{/Subtype /$this->{Subtype}},
			qq{/Rect [ $rect->{Left} $rect->{Bottom} $rect->{Right} $rect->{Top} ] },
			qq{/F $this->{Flag}},
			sprintf( '/P %d 0 R', $this->{PageObj}->getObjId( ) ),
		);
		if( exists $this->{Color} ){
			print $PDF::endln, join( ' ',
				'/C', '[', &PDF::tellColor( $this->{Color} ), ']'
			);
		}
	}
	if( $this->{Opacity} > 0 && $this->{Opacity} < 1 ){
		print $PDF::endln, "/CA $this->{Opacity} ";
	}
	my @strs = map {
		&PDF::escStr( $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{$_} ): $this->{$_} )
	} qw(ModTime Contents Title Name);
	print qq{$PDF::endln/M ($strs[0]) };
	if( $this->{Contents} && $this->{Subtype} ne 'FreeText' ){
		print join( $PDF::endln,
			'',
			qq{/NM ($strs[3]) },
			qq{/Contents ($strs[1]) },
			qq{/Popup $this->{Popup}->{ObjId} 0 R },
		);
		if( ref( $this eq 'Annot' ) && length $this->{Title} ){
			print qq{$PDF::endln/T ($strs[2]) };
		}
	}
	if( { 'StrikeOut' => 1, 'Highlight' => 1, 'Underline' => 1 }->{ $this->{Subtype} } ){
		print qq{$PDF::endln/QuadPoints [ $rect->{Left} $rect->{Bottom} $rect->{Right} $rect->{Bottom} $rect->{Right} $rect->{Top} $rect->{Left} $rect->{Top} ] };
		print qq{$PDF::endln/AP << /N $this->{AP}->{ObjId} 0 R >> };
	} elsif( $this->{Subtype} eq 'Link' ){
		my $str = &PDF::escStr( $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{URI} ): $this->{URI} );
		print join( $PDF::endln,
			'',
			qq{/H /$this->{Highlight} },
			( !defined $this->{Border} || $this->{Border} eq 'None'? '/Border [ 0 0 0 ]': qq{/Border [ 0 0 $this->{Width} $GraphContent::DashPatterns{$this->{Dash}} ]} ),
			'/A <<',
			'/Type /Action',
			'/S /URI',
			qq{/URI ($str)},
			'>> '
		);
	} elsif( $this->{Subtype} eq 'Line' ){
		# Known issue: Line annotations can not be rotated, nor be set with custom color and dash pattern.
		print join( $PDF::endln,
			'',
			qq{/L [ $rect->{Left} $rect->{Bottom} $rect->{Right} $rect->{Top} ] },
			qq{/BS << /W $this->{Width} /S /S >> },
		);
	} elsif( $this->{Subtype} eq 'Stamp' ){
		print join( $PDF::endln,
			'',
			qq{/Name /$this->{IconName}},
		);
		if( $this->{AP} ){
			print qq{$PDF::endln/AP << /N $this->{AP}->{ObjId} 0 R >> };
		}
	} elsif( $this->{Subtype} eq 'Popup' ){
		print join( $PDF::endln,
			'',
			qq{/Open $this->{Open}},
			qq{/Parent $this->{Parent}->{ObjId} 0 R },
		);
	} elsif( $this->{Subtype} eq 'Text' ){
		print join( $PDF::endln,
			'',
			qq{/Name /$this->{IconName} },
		);
		if( $this->{AP} ){
			print qq{$PDF::endln/AP << /N $this->{AP}->{ObjId} 0 R >> };
		}
	} elsif( $this->{Subtype} eq 'FileAttachment' ){
		my $str = &PDF::escStr( $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{File} ): $this->{File} );
		print join( $PDF::endln,
			'',
			qq{/Name /$this->{IconName} },
			qq{/FS << /F ($str) /Type /FileSpec /EF << /F $this->{FileObj}->{ObjId} 0 R >> >> },
		);
		if( $this->{AP} ){
			print qq{$PDF::endln/AP << /N $this->{AP}->{ObjId} 0 R >> };
		}
	} elsif( $this->{Subtype} eq 'FreeText' ){
		print join( $PDF::endln,
			'',
			qq{/Contents ($strs[1]) },
			qq{/T ($strs[2]) },
			qq{/NM ($strs[3]) },
			qq{/AP << /N $this->{AP}->{ObjId} 0 R >> },
			'',
		);
		my $dastr = sprintf( "/%s %d Tf [%.4f %.4f %.4f] rg",
			$PDF::root->getFont( $this->{FontFace}, 'PDFDocEncoding' )->{Name},
			$this->{FontSize}, &Color::tellColor( $this->{FontColor}, 'RGB' ) );
		if( $PDF::root->{Encrypt} ){
			$dastr = &PDF::RC4( $this->{EncKey}, $dastr );
		}
		print qq{/DA (}, &PDF::escStr( $dastr ), qq{) $PDF::endln};
		print qq{/BS << /W $this->{BorderWidth} >> $PDF::endln};
		if( $this->{Rotate} ){
			print qq{/Rotate $this->{Rotate} $PDF::endln};
		}
		if( defined $this->{Align} ){
			printf( "/Q %s $PDF::endln", { Left => 0, Center => 1, Right => 2 }->{ $this->{Align} } || 0 );
		}
	} elsif( $this->{MakeCodeSegment} ){
		&{$this->{MakeCodeSegment}}( $this );
	}
	print join( $PDF::endln,
		'',
		'>> ',
		'endobj',
		''
	);
}

sub startXML {
	my( $this, $dep ) = @_;
	return if( $this->{Auto} );
	print "\t" x $dep, '<', ref( $this ), ' Rect="',
		join( ', ', $this->{rect}->{Left}, $this->{rect}->{Bottom}, $this->{rect}->{Right}, $this->{rect}->{Top} ),
		qq{" Type="$this->{Subtype}" },
		join( ' ', @{$this->{XML}} ), " />\n";
}

sub endXML {
	my( $this, $dep ) = @_;
	return if( $this->{Auto} );
}

sub newFromXML {
	my( $class, $xml ) = @_;
	my @rectsides = split( /,\s*/, $xml->{Rect} );
	if( $xml->{PopupRect} ){
		my @popuprectsides = split( /,\s*/, $xml->{PopupRect} );
		$xml->{PopupRect} = new Rect( @popuprectsides );
	}
	bless $xml, 'HASH';
	if( defined $xml->{Type} && $xml->{Type} ne 'FileAttachment' ){		# For security reason, file attachment is disabled when using XML.
		return new Annot( new Rect( @rectsides ), $xml->{Type}, $xml );
	}
}

sub finalize {
	my $this = shift;
	for( qw(PageObj Parent Popup Contents) ){
		undef $this->{$_};
	}
	@{$this->{XML}} = ( );
}

1;
