#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package Appearance;

use ImageContent;
use PDFStream;
use FloatingText;

@ISA = qw(GraphContent);

%Appearance::AnnotIcons = (
	# File attachment icons
	'PushPin'	=> [ 26, 16, '789c0b0d8582a8a9602a32357425908ac85a35134489864682280606ced0ac552b40d42a0805e541e510d4aa5560ed5343334166866200002350246f' ],
	'Tag'		=> [ 28, 20, '789c0b0dc50ab256ad5ab53234b481818181336b1a03884acd60d05ab58a736a129837356901844a80084278091095116095a969605ee454b029cba0664e85589089c552005747299c' ],
	'Graph'		=> [ 24, 22, '789c0b0d0581ac5540b03281a1818981139d5400932b38e16ab4983a13381a1631ac4c506a6a62d04c6a58055499c5d00122f1980323216a4291000035da26e8' ],
	'Paperclip' => [ 13, 22, '789c0b0d0d0d0d5bb532348c8133344cab33344c1581b3d43a439334706006205e05c4a1403cad33346115676814c352a05953434100005c0d1fdd' ],
	# Text annotation icons
	'Note'		=> [ 20, 24, '789c0b0d450151ab56ad5a1ac1c0c0a08a4470ad5a818fbb02a118acb701c46a980a249a42814427c8d0a5a1680000114c1edb' ],
	'Insert'	=> [ 14, 14, '789c0b0d058248204e82e286a9601cc6a00ac6110c9c609cc0c004c659ab568174840200f4ee10ce' ],
	'Comment'	=> [ 22, 24, '789c0b0d4502ab56ad5a1a1ad6c0c0a0191ac5c0c0c0159a012499a62600490618c9b56a159c441287a884e8829810ba6a01d352a0a1194c20a3a3c0645813d89e4560320b4c4685a20000fe3a286e' ],
	'NewParagraph' => [ 22, 24, '789c0b0d4580ac5540109ac0c0c0c0042439c0a416985cd5002499562d6082cb22910d0aab80e40285a6a6d084150a0d40b20bcc6e5a00126f58d00056d3804d2fc4466400006b772959' ],
	'Paragraph'	=> [ 22, 24, '789c0b0d450751ab802034828181810995645ab50248722d68402399c024830261126202929910bb90010040af274c' ],
	'Key'		=> [ 26, 16, '789c0b0d8583ac95602a8113423181c8b0050c534357cd5ac5b0626918c78a068659aa111c0c0d0cd354a31880609a6a18889aa11aba6a1548094c035c3bcc4c040000293224e6' ],
	'Help'		=> [ 22, 24, '789c55ceb11180201044d19dcbb84ad47e96618c288526c84908a44a5730d00b5ef8f7c8ef8d2e4eb86c40672cc0ce88a30526b4cd98acb8314bd40c2c8f697bf432056a92260153c1115473d556f95de1b87e0ff006a25a24e1' ],
);

sub new {
	my( $class, $oContainer ) = @_;
	my $this = new GraphContent( $oContainer, { 'NoAppend' => 1 } );
	$this->{Stream} = '';
	bless $this, $class;
}

sub showUnderline {
	my( $this, $color, $width, $dash ) = @_;
	$this->saveGState( );
	$this->setColor( $color ) if( defined $color );
	$width ||= 0.5;
	$this->setLineWidth( $width );
	$this->setDash( $dash ) if( $dash );
	if( !$this->{par}->{Dir} ){
		$this->moveTo( 0.5, $width );
		$this->lineTo( $this->{Container}->right( ) - 0.5, $width );
	} elsif( $this->{par}->{Dir} == 1 ){
		$this->moveTo( $this->{Container}->right( ) - $width, 0.5 );
		$this->lineTo( $this->{Container}->right( ) - $width, $this->{Container}->top( ) - 0.5 );
	} elsif( $this->{par}->{Dir} == 2 ){
		$this->moveTo( $this->{Container}->left( ) + $width, 0.5 );
		$this->lineTo( $this->{Container}->left( ) + $width, $this->{Container}->top( ) - 0.5 );
	} elsif( $this->{par}->{Dir} == 3 ){
		$this->moveTo( 0.5, $this->{Container}->top( ) - $width );
		$this->lineTo( $this->{Container}->right( ) - 0.5, $this->{Container}->top( ) - $width );
	}
	$this->restoreGState( );
}

sub showStrikeOut {
	my( $this, $color, $width, $dash ) = @_;
	$this->saveGState( );
	$this->setColor( $color ) if( defined $color );
	$width ||= 1;
	$this->setLineWidth( $width );
	$this->setDash( $dash ) if( $dash );
	if( $this->{par}->{Dir} == 1 || $this->{par}->{Dir} == 2 ){
		$this->moveTo( ( $this->{Container}->width( ) - $width ) / 2, 0.5 );
		$this->lineTo( ( $this->{Container}->width( ) - $width ) / 2, $this->{Container}->top( ) - 0.5 );
	} else {
		$this->moveTo( 1, ( $this->{Container}->height( ) - $width ) / 2 );
		$this->lineTo( $this->{Container}->right( ) - 0.5, ( $this->{Container}->height( ) - $width ) / 2 );
	}
	$this->restoreGState( );
}

sub showHighlight {
	my( $this, $color, $width, $dash ) = @_;
	my( $w, $h ) = ( $this->{Container}->width( ), $this->{Container}->height( ) );
	$width ||= 1;
	$this->saveGState( );
	$this->setColor( $color ) if( defined $color );
#	$this->setLineWidth( $width );
	$this->moveTo( 1, 1 );
	$this->drawRect( $w - 1, $h - 1 );
	$this->closePath( );
#	$this->moveTo( $width / 2, $width / 2 );
#	$this->drawRect( $w - $width, $h - $width );
	$this->restoreGState( );
}

sub showIcon {
	my( $this, $type ) = @_;
	my $icon = $Appearance::AnnotIcons{$type};
	my @colors = ( );
	map {
		push( @colors, &Color::tellColor( $_, 'RGB' ) );
	} ( $this->{par}->{Color}, 'White', 'Black', 'Red' );	# The last one in not used at all
	$this->showInlineImage(		# Show icon as an inline image
		new ImageContent(
			new PDFStream(			# Use the encoded data to build an image (always 4-color)
				pack( 'H*', $icon->[2] ),
				{ 'Filters' => [ 'FlateDecode' ], 'DecodeParms' => [ 'null' ], 'InternalUse' => 1 }
			), $icon->[0], $icon->[1], {
				'BitsPerComponent' => 2, 'Type' => 'Indexed', 'Inline' => 1,
				'ColorTable' => join( '', map{ chr( int( $_ * 255 ) ) } @colors )
			}
		), 0, 0 );
}

sub showStamp {
	my( $this, $name ) = @_;
	my $skewangle = $this->{par}->{SkewAngle} * 3.1416 / 180;
	my $tg = sin( $skewangle ) / cos( $skewangle );
	$this->saveGState( );
	$this->setColor( $this->{par}->{Color}, 0, 'RGB' );
	$this->setLineWidth( 2 );
	my $attr = { 'FontFace'=>$this->{par}->{FontFace}, 'FitWidth'=>'CharScaling', 'FitHeight'=>'Stretch', 'Color'=>$this->{par}->{Color} };
	if( $this->{par}->{SkewDir} eq 'X' ){
		my $h = $this->{Container}->height( );
		my $w = $this->{Container}->width( ) - $h * $tg;
		$this->{Stream} .= sprintf( qq{${PDF::endln}1 0 %.4f 1 0 0 cm${PDF::endln}}, $tg );
		$this->moveTo( $w / 2, $h / 2 );
		$this->drawRoundedRect( $w - 4, $h - 4, 4, 0, 1 );
		$attr->{Width} = $w - 8;
		$attr->{Height} = $h - 8;
		$this->showText( 4, $h + 2, $name, $attr );
	} else {
		my $w = $this->{Container}->width( );
		my $h = $this->{Container}->height( ) - $w * $tg;
		$this->{Stream} .= sprintf( qq{${PDF::endln}1 %.4f 0 1 0 0 cm${PDF::endln}}, $tg );
		$this->setColor( $this->{par}->{Color}, 0, 'RGB' );
		$this->setLineWidth( 2 );
		$this->moveTo( $w / 2, $h / 2 );
		$this->drawRoundedRect( $w - 4, $h - 4, 4, 0, 1 );
		$attr->{Width} = $w - 8;
		$attr->{Height} = $h - 8;
		$this->showText( 4, $h + 2, $name, $attr );
	}
	$this->restoreGState( );
}

sub drawBorder {
	my $this = shift;
	my( $w, $h ) = ( $this->{Container}->width( ), $this->{Container}->height( ) );
	my $par = $this->{par};
	my $bw = $par->{BorderWidth};
	my $style = $par->{BorderStyle};
# Step 1: Draw background
	$this->setColor( $par->{BgColor}, 1 );
	$this->moveTo( 0, 0, 1 );
	$this->drawRect( $w, $h, 1 );
	return if( $style eq 'N' );
# Step 2: Draw outline or underline
	$this->setLineWidth( $bw );
	if( $style ne 'S' && $par->{BorderDash} ){
		$this->setDash( $par->{BorderDash} );
	}
	$this->setColor( $par->{BorderColor} );
	$this->moveTo( $bw / 2, $bw / 2 );
	if( $style eq 'U' ){
		$this->lineTo( $w - $bw / 2, $bw / 2 );
	} elsif( $style ne 'B' && $style ne 'I' || $par->{BorderColor} || $par->{BorderDash} ){
		$this->drawRect( $w - $bw, $h - $bw );
	}
# Step 3: Draw inset or bevel
	if( $style eq 'B' || $style eq 'I' ){
		$this->setColor( ( $style eq 'I'? &Color::darken( $par->{BgColor}, 0.5 ): 'White' ), 1 );
		$this->moveTo( $bw, $bw );
		$this->connectTo( $bw, $h - $bw );
		$this->connectTo( $w - $bw, $h - $bw );
		$this->connectTo( $w - 2 * $bw, $h - 2 * $bw );
		$this->connectTo( 2 * $bw, $h - 2 * $bw );
		$this->connectTo( 2 * $bw, 2 * $bw );
		$this->closeSubPath( );
		$this->fill( );
		$this->setColor( ( $style eq 'I'? 'White': &Color::darken( $par->{BgColor}, 0.5 ) ), 1 );
		$this->moveTo( $bw, $bw );
		$this->connectTo( $w - $bw, $bw );
		$this->connectTo( $w - $bw, $h - $bw );
		$this->connectTo( $w - 2 * $bw, $h - 2 * $bw );
		$this->connectTo( $w - 2 * $bw, 2 * $bw );
		$this->connectTo( 2 * $bw, 2 * $bw );
		$this->closeSubPath( );
		$this->fill( );
		$this->closePath( );
		$this->moveTo( $bw, $bw );
		$this->drawRect( $w - $bw, $h - $bw, 3 );
	}
}

sub showButton {
	my( $this, $isdown ) = @_;
	my( $w, $h ) = ( $this->{Container}->width( ), $this->{Container}->height( ) );
	my $par = $this->{par};
	my $bw = $par->{BorderWidth};
	if( $par->{Highlight} ne 'P' ){
		$isdown = 0;
	}
	$isdown ||= 0;
	if( $isdown ){
		if( $par->{BorderStyle} eq 'B' ){
			$par->{BorderStyle} = 'I';
			$this->drawBorder( );
			$par->{BorderStyle} = 'B';
		} elsif( $par->{BorderStyle} eq 'I' ){
			my $c = $par->{BgColor};
			$par->{BgColor} = &Color::darken( $par->{BgColor}, 0.3 );
			$this->drawBorder( );
			$par->{BgColor} = $c;
		}
	} else {
		$this->drawBorder( );
	}
	if( $isdown ){
		$this->{Stream} .= "1 0 0 1 1 -1 cm $GraphContent::endln";
	}
	my $len = $par->{Font}->getWordWidth( $par->{Caption}, $par->{FontSize} );
	my( $tx, $ty ) = ( ( $w - $len ) / 2, ( $h - $par->{FontSize} ) / 2 - $par->{FontSize} * $par->{Font}->{FontPtr}->{FontDescriptor}->{FontBBox}->[1] / 1000 );
	if( $par->{Icon} ){
		my( $dw, $dh ) = ( $par->{Icon}->{DisplayWidth}, $par->{Icon}->{DisplayHeight} );
		my( $ix, $iy ) = ( ( $w - $dw ) / 2 - $bw, ( $h - $dh ) / 2 - $bw );
		if( $par->{IconPos} eq 'Left' ){
			$ix = &PDF::max( ( $w - $bw * 6 - $len - $dw ) / 2, 0 ) + 2 * $bw;
			$tx += ( $w - $len ) / 2 - $ix;
		} elsif( $par->{IconPos} eq 'Right' ){
			$ix = $w - &PDF::max( ( $w - $bw * 6 - $len - $dw ) / 2, 0 ) - $dw - 2 * $bw;
			$tx = $w - $dw - $ix;
		} elsif( $par->{IconPos} eq 'Bottom' ){
			$iy = &PDF::max( ( $h - $bw * 6 - $par->{FontSize} - $dh ) / 2, 0 ) + 2 * $bw;
			$ty = $h - $par->{FontSize} - $iy;
		} elsif( $par->{IconPos} eq 'Top' ){
			$iy = $h - &PDF::max( ( $h - $bw * 6 - $par->{FontSize} - $dh ) / 2, 0 ) - $dh - 2 * $bw;
			$ty = $h - $dh - $iy;
		} elsif( $par->{IconPos} eq 'Stretch' ){
			$ix = $iy = $bw;
		} elsif( $par->{IconPos} eq 'Fit' ){
			if( $w > $h ){ $iy = $bw; } else { $ix = $bw; }
		}
		$this->showInlineImage( $par->{Icon}, $ix, $iy );
	}
	my $ground = { qw(CMYK k RGB rg Gray g) }->{ $PDF::root->{Prefs}->{ColorSpace} || 'RGB' };
	my $txt = &PDF::escStr( $par->{Caption} );
	$this->{Stream} .= join( ' ',
		'BT',
		qq{/$par->{Font}->{Name} $par->{FontSize} Tf},
		qq{$par->{FontSize} TL},
		&Color::tellColor( $par->{FontColor}, ( $PDF::root->{Prefs}->{ColorSpace} || 'RGB' ) ),
		$ground,
		'1 0 0 1', sprintf( '%.4f %.4f', $tx, $ty ),
		'Tm',
		qq{($txt) Tj},
		'ET',
		''
	);
}

sub showCheckBox {
	my( $this, $ischecked, $isdown ) = @_;
	my $par = $this->{par};
	my $bw = $par->{BorderWidth};
	$isdown ||= 0;
	$ischecked ||= 0;
	my( $w, $h ) = ( $this->{Container}->width( ), $this->{Container}->height( ) );
	if( $isdown ){
		if( $par->{BorderStyle} eq 'B' ){
			$par->{BorderStyle} = 'I';
			$this->drawBorder( );
			$par->{BorderStyle} = 'B';
		} else {
			my $c = $par->{BgColor};
			$par->{BgColor} = &Color::darken( $par->{BgColor}, 0.3 );
			$this->drawBorder( );
			$par->{BgColor} = $c;
		}
	} else {
		$this->drawBorder( );
	}
	return unless( $ischecked );
	if( !$par->{Symbol} ){
		$this->setLineWidth( $bw );
		$this->setColor( $par->{BorderColor}, 1 );
		$this->setDash( $par->{BorderDash} ) if( $par->{BorderDash} );
		$this->moveTo( $bw / 2, $bw / 2 );
		$this->lineTo( $w - $bw / 2, $h - $bw / 2, 1 );
		$this->moveTo( $bw / 2, $h - $bw / 2 );
		$this->lineTo( $w - $bw / 2, $bw / 2 );
		return;
	}
	my $ground = { qw(CMYK k RGB rg Gray g) }->{ $PDF::root->{Prefs}->{ColorSpace} || 'RGB' };
	my $str = &PDF::escStr( substr( $par->{Symbol}, 0, 1 ) );
	$this->{Stream} .= join( ' ',
		'BT',
		qq{/$par->{Font}->{Name} $par->{FontSize} Tf},
		qq{$par->{FontSize} TL},
		&Color::tellColor( $par->{FontColor}, ( $PDF::root->{Prefs}->{ColorSpace} || 'RGB' ) ),
		$ground,
		'1 0 0 1',
		( $w - $par->{Font}->getWordWidth( $par->{Symbol}, $par->{FontSize} ) ) / 2,
		( $h - $par->{FontSize} ) / 2 - $par->{FontSize} * $par->{Font}->{FontPtr}->{FontDescriptor}->{FontBBox}->[1] / 1000,
		'Tm',
		qq{($str) Tj},
		'ET',
		''
	);
}

sub showRadio {
	my( $this, $ischecked, $isdown ) = @_;
	my( $w, $h ) = ( $this->{Container}->width( ), $this->{Container}->height( ) );
	$isdown ||= 0;
	$ischecked ||= 0;
	my $r = &PDF::min( $w, $h ) / 2;
	my $par = $this->{par};
	my $bw = $par->{BorderWidth};
	my $style = $par->{BorderStyle};
	$this->setColor( ( $isdown? &Color::darken( $par->{BgColor}, 0.3 ): $par->{BgColor} ), 1 );
	$this->moveTo( $w / 2, $h / 2 );
	$this->drawCircle( $r, 1 );
	if( $style ne 'N' ){
		$this->setLineWidth( $bw );
		if( $style ne 'S' && $par->{BorderDash} ){
			$this->setDash( $par->{BorderDash} );
		}
		$this->setColor( $par->{BorderColor} );
		$this->drawCircle( $r - $bw / 2 );
		if( $style eq 'B' || $style eq 'I' ){
			$this->setColor( ( $style eq 'I'? 'White': &Color::darken( $par->{BgColor}, 0.5 ) ), !$ischecked );
			$this->drawCircle( $r - $bw, !$ischecked );
			$this->setColor( ( $style eq 'I'? &Color::darken( $par->{BgColor}, 0.5 ): 'White' ), !$ischecked );
			$this->drawArc( $r - $bw, 45, 225, !$ischecked );
			if( !$ischecked ){
				$this->setColor( ( $isdown? &Color::darken( $par->{BgColor}, 0.3 ): $par->{BgColor} ), 1 );
				$this->moveTo( $w / 2, $h / 2 );
				$this->drawCircle( $r - $bw * 2, 1 );
			}
		}
	}
	return unless( $ischecked );
	if( !$par->{Symbol} ){
		$this->setColor( ( $par->{BorderColor} || $this->{par}->{FontColor} ), 1 );
		$this->drawCircle( ( $r - $bw ) * 0.6, 1 );
		return;
	}
	my $ground = { qw(CMYK k RGB rg Gray g) }->{ $PDF::root->{Prefs}->{ColorSpace} || 'RGB' };
	my $str = &PDF::escStr( substr( $par->{Symbol}, 0, 1 ) );
	$this->{Stream} .= join( ' ',
		'BT',
		qq{/$par->{FontName} $par->{FontSize} Tf},
		qq{$par->{FontSize} TL},
		&Color::tellColor( $par->{FontColor}, ( $PDF::root->{Prefs}->{ColorSpace} || 'RGB' ) ),
		$ground,
		'1 0 0 1',
		( $w - $par->{FontSize} / 1000 * $par->{Font}->{FontPtr}->{Widths}->[ ord( $par->{Symbol} ) - $par->{Font}->{FontPtr}->{FirstChar} ] ) / 2,
		( $h - $par->{FontSize} ) / 2 - $par->{FontSize} * $par->{Font}->{FontPtr}->{FontDescriptor}->{FontBBox}->[1] / 1000,
		'Tm',
		qq{($str) Tj},
		'ET',
		''
	);
}

sub showTextEdit {
	my $this = shift;
	my $par = $this->{par};
	my $bw = $par->{BorderWidth};
	$this->drawBorder( );
	$this->{Stream} .= '/Tx BMC ';
	$this->saveGState( );
	$this->moveTo( $bw, $bw, 1 );
	$this->drawRect( $this->{Container}->width( ) - $bw * 2, $this->{Container}->height( ) - $bw * 2, 3 );
	$this->intersect( );
	$this->closePath( );
	my $txt = $par->{DesiredType} eq 'Password'? ( '*' x length( $par->{Value} ) ): $par->{Value};
	my $wid = $par->{Font}->{FontPtr}->{Widths};
	my $fc = $par->{Font}->{FontPtr}->{FirstChar};
	my $w = ( $this->{Container}->{Width} - $bw * 4 ) / $par->{FontSize} * 1000;	# Available width in font definition's measurement
	if( $par->{BorderStyle} eq 'B' || $par->{BorderStyle} eq 'I' ){
		$w -= $bw * 2;
	}
	my @lines = ( );
	if( $par->{DesiredType} eq 'TextArea' ){
		my @paras = split( /\n|\r/, $txt );
		foreach my $para ( @paras ){
			while( length( $para ) ){
				my $i = 0;
				my $sum = 0;
				while( $sum <= $w && $i < length( $para ) ){
					$sum += $wid->[ ord( substr( $para, $i++, 1 ) ) - $fc ];
				}
				$i--;
				unless( substr( $para, $i, 1 ) =~ /\s/ || substr( $para, 0, $i ) !~ /(?<=\S)\s/ || $i == length( $para ) - 1 ){
					while( substr( $para, $i, 1 ) !~ /\s/ ){ $i--; }
				}
				$i++;
				push( @lines, substr( $para, 0, $i, '' ) );
			}
			push( @lines, '' );
		}
	} else {
		push( @lines, $txt );
	}
	@lines = &PDF::escStr( @lines );
	my $ground = { qw(CMYK k RGB rg Gray g) }->{ $PDF::root->{Prefs}->{ColorSpace} || 'RGB' };
	my $vpos = $par->{DesiredType} eq 'TextArea'?
		$this->{Container}->{Height} - 2 * $bw:
		( ( $this->{Container}->{Height} - $par->{FontSize} ) / 2 - $par->{FontSize} * $par->{Font}->{FontPtr}->{FontDescriptor}->{Descent} / 1000 );
	$this->{Stream} .= join( ' ',
		'BT',
		qq{/$par->{Font}->{Name} $par->{FontSize} Tf},
		$par->{FontSize}, 'TL',
		&Color::tellColor( $par->{FontColor} ), $ground,
		'1 0 0 1 ',
		sprintf( '1 0 0 1 %.4f %.4f', $bw * 2, $vpos ),
		'Tm',
		'(' . join( ")'$PDF::endln(", @lines ) . ') Tj',
		'ET',
		''
	);
	$this->restoreGState( );
	$this->{Stream} .= 'EMC ';
}

sub showListBox {
	my $this = shift;
	my( $par, $w, $h ) = ( $this->{par}, $this->{Container}->width( ), $this->{Container}->height( ) );
	my $bw = $par->{BorderWidth};
	$this->drawBorder( );
	$this->saveGState( );
	$this->moveTo( $bw, $bw );
	$this->drawRect( $w - $bw, $h - $bw, 3 );
	$this->intersect( );
	$this->closePath( );
	$this->{Stream} .= '/Tx BMC ';
	my $str = &PDF::escStr( $par->{Choices}->[ $par->{Selected} ]->[0] );
	my $fd = $par->{Font}->{FontPtr}->{FontDescriptor};
	my $ground = { qw(CMYK k RGB rg Gray g) }->{ $PDF::root->{Prefs}->{ColorSpace} || 'RGB' };
	if( $par->{DesiredType} eq 'Combo' ){
		$this->{Stream} .= join( ' ',
			'BT',
			'/' . $par->{FontName}, $par->{FontSize}, 'Tf',
			&Color::tellColor( $par->{FontColor} ), $ground,
			sprintf( '1 0 0 1 %.4f %.4f', $bw * 2, ( $h - $par->{FontSize} ) / 2 - $par->{FontSize} * $fd->{Descent} / 1000 ),
			'Tm',
			qq{($str) Tj},
			'ET',
			'',
		);
		$this->restoreGState( );
		$this->{Stream} .= 'EMC ';
		return;
	}
	my $leading = $par->{FontSize} * ( 1 + ( $fd->{FontBBox}->[3] - $fd->{FontBBox}->[1] - 1000 ) / 1000 );
	my $vpos = $h - $bw - $leading;
	if( ( $par->{Selected} + 1 ) * $leading > $vpos ){
		$vpos += ( $par->{Selected} - int( $h / $leading ) ) * $leading;
	}
	$this->setColor( 'DarkBlue', 1 );
	$this->moveTo( $bw, $vpos - $par->{Selected} * $leading, 1 );
	$this->drawRect( $w - $bw * 2, $leading, 1 );
	$this->{Stream} .= join( ' ',
		'BT',
		'/' . $par->{FontName}, $par->{FontSize}, 'Tf',
		sprintf( '1 0 0 1 %.4f %.4f', $bw * 2, $vpos ),
		'Tm',
		&Color::tellColor( $par->{FontColor} ), $ground,
		'',
	);
	my @strs = &PDF::escStr( map { $_->[0] } @{$par->{Choices}} );
	$this->{Stream} .= sprintf( '0 %.4f Td ', ( $leading - $par->{FontSize} ) / 2 );
	for my $i ( 0..$#strs ){
		if( $i == $par->{Selected} ){
			$this->{Stream} .= join( ' ',
				&Color::tellColor( 'White' ), $ground,
				'(' . $strs[$i] . ')', 'Tj T*',
				&Color::tellColor( $par->{FontColor} ), $ground,
				'',
			);
		} else {
			$this->{Stream} .= join( ' ',
				'(' . $strs[$i] . ')', 'Tj T*',
				'',
			);
		}
		$this->{Stream} .= sprintf( '0 %.4f Td ', 0 - $leading );
	}
	$this->{Stream} .= ' ET ';
	$this->restoreGState( );
	$this->{Stream} .= ' EMC ';
}

sub showFreeText {
	my $this = shift;
	my $par = $this->{par};
	my $attr = {
		FontFace => $par->{FontFace},
		Encoding => 'PDFDocEncoding',
		FontSize => $par->{FontSize},
		Color => $par->{FontColor},
		BgColor => $par->{Color},
		TextJustify => ucfirst( lc $par->{Align} ),
		InternalUse => 1,
	};
	if( $par->{BorderWidth} ){
		$attr->{BorderWidth} = $par->{BorderWidth};
		$attr->{BorderColor} = $par->{FontColor};
	}
	my $tbox = new FloatingText( $this->{Container}, $par->{Contents}, $attr );
	$this->{Stream} = $tbox->{Stream};
	$this->{Resources}->merge( $tbox->{Resources} );
}

sub customCode {
	my $this = shift;
	print join( $PDF::endln,
		'',
		'/Type /XObject ',
		'/Subtype /Form ',
		'/FormType 1 ',
		qq{/BBox [ 0 0 $this->{Container}->{Width} $this->{Container}->{Height} ] },
		'/Resources << /ProcSet [ /PDF /Text ] ',
	);
	if( $this->{par}->{FontFace} ){
		my $oFont = $PDF::root->getFont( $this->{par}->{FontFace}, 'PDFDocEncoding' );
		$this->{Resources}->{Font}->{ $oFont->{Name} } = 1;
	}
	for my $res ( keys %{$this->{Resources}} ){
		next unless( scalar keys %{$this->{Resources}->{$res}} );
		print qq{$PDF::endln/$res << };
		print map { my $obj = $PDF::root->getObjByName( $_ ); sprintf( "/%s %d 0 R ", $obj->{Name}, $obj->{ObjId} ); } keys %{$this->{Resources}->{$res}};
		print '>> ';
	}
	print '>> ';
}

sub makeCode {
	my $this = shift;
	$this->SUPER::makeCode( );
}

# Used to disable the same functions in parent class because Apperance objects will NOT produce XML.
sub startXML { }
sub endXML { }

package WinXPAppearance;

use PDFStream;
use PDFShading;

@ISA = qw(Appearance);
%WinXPAppearance::XPShadings = ( );

sub getShading {
	my $this = shift;
	my $type = shift;
	my %parms = (
		Down => [ 'LightGrey', 'White', 'T->B' ],
		Normal => [ 'C6C6D6', 'White', 'B->T' ],
		Halo => [ 'FFF7CE', 'FFB531', 'T->B' ],
		DownTilt => [ 'B5B5A5', 'B5B5A5', 'TL->BR' ],
		NormalTilt => [ 'DEDED6', 'FFFFFF', 'TL->BR' ],
		HaloTilt => [ 'FFF7CE', 'FFB531', 'TL->BR' ],
		RadioDot => [ 'White', 'Green', 'TL->BR' ],
	);
	if( !exists $WinXPAppearance::XPShadings{ $type } ){
		my $obj = $PDF::root->getObjByName( 'WinXP_' . $type );
		if( !defined $obj || ref( $obj ) ne 'PDFShading' ){
			$obj = new PDFShading( 'Linear', { FromColor => $parms{$type}->[0], ToColor => $parms{$type}->[1],
				Dir => $parms{$type}->[2], Name => 'WinXP_' . $type } );
		}
		$WinXPAppearance::XPShadings{ $type } = $obj;
	}
	return $WinXPAppearance::XPShadings{ $type };
}

sub showButton {
	my( $this, $isdown ) = @_;
	my( $w, $h ) = ( $this->{Container}->width( ), $this->{Container}->height( ) );
	my $par = $this->{par};
	my $bw = $par->{BorderWidth};
	$this->setColor( $par->{BorderColor} );
	$this->setLineWidth( $bw );
	$this->moveTo( 2, 2 );
	$this->drawRoundedRect( $w - 4, $h - 4, 2 );
	$this->newPath( );
	$this->gradFill( $this->getShading( $isdown == 1? 'Down': 'Normal' ),
		new Rect( 4, 4, $w - 4, $h - 4 ) );
	$this->newPath( );
	if( $isdown == 2 ){
		$this->drawPolyLine( 3, 6, 6, $w - 6, 6, $w - 6, $h - 6, 6, $h - 6 );
		$this->gradFill( $this->getShading( 'Halo' ),
			new Rect( 4, 4, $w - 4, $h - 4 ) );
		$this->newPath( );
	}
	my $len = $par->{Font}->getWordWidth( $par->{Caption}, $par->{FontSize} );
	my( $tx, $ty ) = ( ( $w - $len ) / 2, ( $h - $par->{FontSize} ) / 2 - $par->{FontSize} * $par->{Font}->{FontPtr}->{FontDescriptor}->{FontBBox}->[1] / 1000 );
	if( $par->{Icon} ){
		my( $dw, $dh ) = ( $par->{Icon}->{DisplayWidth}, $par->{Icon}->{DisplayHeight} );
		my( $ix, $iy ) = ( ( $w - $dw ) / 2 - $bw, ( $h - $dh ) / 2 - $bw );
		if( $par->{IconPos} eq 'Left' ){
			$ix = &PDF::max( ( $w - $bw * 6 - $len - $dw ) / 2, 0 ) + 2 * $bw;
			$tx += ( $w - $len ) / 2 - $ix;
		} elsif( $par->{IconPos} eq 'Right' ){
			$ix = $w - &PDF::max( ( $w - $bw * 6 - $len - $dw ) / 2, 0 ) - $dw - 2 * $bw;
			$tx = $w - $dw - $ix;
		} elsif( $par->{IconPos} eq 'Bottom' ){
			$iy = &PDF::max( ( $h - $bw * 6 - $par->{FontSize} - $dh ) / 2, 0 ) + 2 * $bw;
			$ty = $h - $par->{FontSize} - $iy;
		} elsif( $par->{IconPos} eq 'Top' ){
			$iy = $h - &PDF::max( ( $h - $bw * 6 - $par->{FontSize} - $dh ) / 2, 0 ) - $dh - 2 * $bw;
			$ty = $h - $dh - $iy;
		} elsif( $par->{IconPos} eq 'Stretch' ){
			$ix = $iy = $bw;
		} elsif( $par->{IconPos} eq 'Fit' ){
			if( $w > $h ){ $iy = $bw; } else { $ix = $bw; }
		}
		$this->showInlineImage( $par->{Icon}, $ix, $iy );
	}
	my $ground = { qw(CMYK k RGB rg Gray g) }->{ $PDF::root->{Prefs}->{ColorSpace} || 'RGB' };
	my $txt = &PDF::escStr( $par->{Caption} );
	$this->{Stream} .= join( ' ',
		'BT',
		qq{/$par->{Font}->{Name} $par->{FontSize} Tf},
		qq{$par->{FontSize} TL},
		&Color::tellColor( $par->{FontColor}, ( $PDF::root->{Prefs}->{ColorSpace} || 'RGB' ) ),
		$ground,
		'1 0 0 1', sprintf( '%.4f %.4f', $tx, $ty ),
		'Tm',
		qq{($txt) Tj},
		'ET',
		''
	);
}

sub showCheckBox {
	my( $this, $ischecked, $isdown ) = @_;	# $isdown = 0, 1, 2 (false, true, rollover)
	my $par = $this->{par};
	my $bw = $par->{BorderWidth};
	$isdown ||= 0;
	$ischecked ||= 0;
	my( $w, $h ) = ( $this->{Container}->width( ), $this->{Container}->height( ) );
	if( $isdown < 2 ){
		$this->gradFill( $this->getShading( $isdown? 'DownTilt': 'NormalTilt' ),
			new Rect( 2, 2, $w - 2, $h - 2 ) );
		$this->newPath( );
	}
	$this->setColor( $this->{par}->{BorderColor} );
	$this->setLineWidth( $par->{BorderWidth} || 2 );
	$this->moveTo( 1, 1 );
	if( $isdown == 2 ){
		$this->setColor( ( $ischecked? 'E7E7E7': 'FFFFF7' ), 1 );
		$this->drawRectTo( $w - 1, $h - 1, 2 );
		$this->drawPolyLine( 3, 3, 3, $w - 3, 3, $w - 3, $h - 3, 3, $h - 3 );
		$this->gradFill( $this->getShading( 'HaloTilt' ),
			new Rect( 1, 1, $w - 1, $h - 1 ) );
	} else {
		$this->moveTo( 1, 1 );
		$this->drawRect( $w - 2, $h - 2 );
	}
	my $ground = { qw(CMYK k RGB rg Gray g) }->{ $PDF::root->{Prefs}->{ColorSpace} || 'RGB' };
	$this->newPath( );
	return if( !$ischecked );
	if( !$par->{Symbol} ){
		$this->setLineWidth( $bw );
		$this->setColor( $par->{BorderColor}, 1 );
		$this->setDash( $par->{BorderDash} ) if( $par->{BorderDash} );
		$this->moveTo( $bw / 2 + 3, $bw / 2 + 3 );
		$this->lineTo( $w - $bw / 2 - 3, $h - $bw / 2 - 3, 1 );
		$this->moveTo( $bw / 2 + 3, $h - $bw / 2 - 3 );
		$this->lineTo( $w - $bw / 2 - 3, $bw / 2 + 3 );
		return;
	}
	$this->setLineWidth( 1 );
	my $str = &PDF::escStr( substr( $par->{Symbol}, 0, 1 ) );
	$this->{Stream} .= join( ' ',
		'BT',
		qq{/$par->{Font}->{Name} $par->{FontSize} Tf},
		qq{$par->{FontSize} TL},
		&Color::tellColor( $par->{FontColor}, ( $PDF::root->{Prefs}->{ColorSpace} || 'RGB' ) ),
		$ground,
		'1 0 0 1',
		( $w - $par->{Font}->getWordWidth( $par->{Symbol}, $par->{FontSize} ) ) / 2,
		( $h - $par->{FontSize} ) / 2 - $par->{FontSize} * $par->{Font}->{FontPtr}->{FontDescriptor}->{FontBBox}->[1] / 1000,
		'Tm',
		qq{($str) Tj},
		'ET',
		''
	);
}

sub showRadio {
	my( $this, $ischecked, $isdown ) = @_;
	my( $w, $h ) = ( $this->{Container}->width( ), $this->{Container}->height( ) );
	my $r = &PDF::min( $w / 2, $h / 2 );
	$isdown ||= 0;
	$ischecked ||= 0;
	my $par = $this->{par};
	my $bw = $par->{BorderWidth};
	if( $isdown < 2 ){
		$this->gradFill( $this->getShading( $isdown? 'DownTilt': 'NormalTilt' ),
			new Rect( 2, 2, $w - 2, $h - 2 ) );
		$this->newPath( );
		$this->setColor( 'white', 1 );
		$this->moveTo( 0, 0 );
		$this->drawRect( $w, $h, 3 );
		$this->moveTo( $w / 2, $h / 2 );
		$this->drawCircle( $r - 2, 3, 1 );
		$this->fill( );
		$this->newPath( );
		$this->setColor( $par->{BorderColor} );
		$this->setLineWidth( $bw );
		$this->moveTo( $w / 2, $h / 2 );
		$this->drawCircle( $r - 1 );
	} else {
		$this->gradFill( $this->getShading( 'HaloTilt' ),
			new Rect( 1, 1, $w - 1, $h - 1 ) );
		$this->newPath( );
		$this->setColor( 'white', 1 );
		$this->moveTo( 0, 0 );
		$this->drawRect( $w, $h, 3 );
		$this->moveTo( $w / 2, $h / 2 );
		$this->drawCircle( $r - 2, 3, 1 );
		$this->fill( );
		$this->newPath( );
		$this->setColor( $par->{BorderColor} );
		$this->setColor( ( $ischecked? 'E7E7E7': 'FFFFF7' ), 1 );
		$this->setLineWidth( $bw );
		$this->moveTo( $w / 2, $h / 2 );
		$this->drawCircle( $r - 1 );
		$this->moveTo( $w / 2, $h / 2 );
		$this->drawCircle( $r - 5, 1 );
	}
	return unless( $ischecked );
	if( !$par->{Symbol} ){
		my $cr = $r * 0.4;
		$this->newPath( );
		$this->moveTo( $w / 2, $h / 2 );
		$this->intersect( );
		$this->drawCircle( $cr, 3 );
		$this->closePath( );
		$this->gradFill( $this->getShading( 'RadioDot' ),
			new Rect(  $w / 2 - $cr, $h / 2 - $cr,  $w / 2 + $cr, $h / 2 + $cr ), 1 );
		$this->fill( );
		return;
	}
	my $ground = { qw(CMYK k RGB rg Gray g) }->{ $PDF::root->{Prefs}->{ColorSpace} || 'RGB' };
	my $str = &PDF::escStr( substr( $par->{Symbol}, 0, 1 ) );
	$this->{Stream} .= join( ' ',
		'BT',
		qq{/$par->{FontName} $par->{FontSize} Tf},
		qq{$par->{FontSize} TL},
		&Color::tellColor( $par->{FontColor}, ( $PDF::root->{Prefs}->{ColorSpace} || 'RGB' ) ),
		$ground,
		'1 0 0 1',
		( $w - $par->{FontSize} / 1000 * $par->{Font}->{FontPtr}->{Widths}->[ ord( $par->{Symbol} ) - $par->{Font}->{FontPtr}->{FirstChar} ] ) / 2,
		( $h - $par->{FontSize} ) / 2 - $par->{FontSize} * $par->{Font}->{FontPtr}->{FontDescriptor}->{FontBBox}->[1] / 1000,
		'Tm',
		qq{($str) Tj},
		'ET',
		''
	);
}

1;
