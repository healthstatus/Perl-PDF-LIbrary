#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package TextContent;

@ISA = qw(PDFStream);

use Shape;
use GraphContent;
use Annot;
use Outlines;

@TextContent::TextBank = ( );
$TextContent::endln = "\x0D\x0A";
$TextContent::InStyle = 0;
@TextContent::SaveAttribs = qw(Font Size Color VerticalAlign TextJustify Leading);
@TextContent::Styles = ( );
@TextContent::ChangedAttribs = ( );
@TextContent::Paragraphs = ( );
$TextContent::ContinuedPara = 0;
@TextContent::Ranges = ( );
@TextContent::LastRanges = ( );
@$TextContent::AnnotBoxes = ( );
$TextContent::pFont = 0;	# Current PDFFont object

sub new {
	my( $class, $parm, $attr ) = @_;
	if( ref( $parm ) eq $class ){		# Copy constructing
		my $this = {
			'Stream' => '',
			'Container' => $parm->{Container},
			'XML' => $parm->{XML},		# Note this is a reference to array
			'IsCopy' => 1,				# To indicate it is created from the template
			'IsTemplate' => 0,
			'x' => 0,
			'y' => 0,
			'Filters' => [ ],
			'ParaPos' => [ ],
			'Name' => '',
			'LineBuffer' => {
				TextStart => 0,
				TextAlign => 'Left',
				TextLen   => 0,
				PDFCode   => '',
				NumTabs   => 0,
			 },
			'Resources' => new Resources( $param->{Resources} ),
			'ZIndex' => ( defined $attr && ref( $attr ) eq 'HASH' && exists $attr->{ZIndex} )? $attr->{ZIndex}: 0,
		};
		bless $this, $class;
		$this->setName( ref( $attr ) eq 'HASH' && $attr->{Name}? $attr->{Name}: '' );
		$parm->{Stream} =~ /^(.(?!BT))*/s;	# Copy codes before "BT"
		$this->{Stream} = $& . " BT $TextContent::endln";	# Spaces make it safer.
		for( qw(ExtraParaSpacing Font Leading Rotation Size TextDir TextJustify VerticalAlign Voracious Opacity BlendMode
			WordSpacing CharSpacing Color BodyIndent ContentPadding FirstIndent PaddingLeft PaddingRight TabPosition Encoding) ){
			$this->{$_} = $parm->{$_};
		}
		for( qw(Dirty TracePos LeftX LeftY RightX RightY LastSpace Indent) ){
			$this->{$_} = 0;
		}
		for my $res ( keys %{$this->{Resources}} ){
			for( keys %{$parm->{Resources}->{$res}} ){
				$this->{Resources}->{$res}->{$_} = 1;
			}
		}
		$PDF::root->{CurrPage}->appendContent( $this );
		return $this;
	}	
	my $oFont = $PDF::root->getFont( ( $attr->{FontFace} || $PDF::root->{Prefs}->{FontFace} || 'Times-Roman' ),
		( $attr->{Encoding} || 'WinAnsiEncoding' ) );
	my @xmls = ( );
	if( ref( $parm ) eq 'Rect' ){
		push( @xmls, 'Rect="' . join( ', ', 
				$parm->left( ), $parm->bottom( ),
				$parm->right( ), $parm->top( ) ) . '"' );
	} else {
		push( @xmls, 'Poly="' . join( ', ', $parm->getPoints( ) ) . '"' );
	}
	if( ref( $parm ) eq 'Poly' && $attr->{TextDir} ){
		&PDF::PDFError( $class, "Text block using Poly as the container can NOT be flipped." );
	}
	my $this = {
		'Annots' => [ ],
		'CharSpacing' => &PDF::tellSize( $attr->{CharSpacing} || 0 ),
		'Code' => '',
		'Color' => '000000',
		'Container' => $parm,
		'ExtraParaSpacing' => ( $attr->{ExtraParaSpacing} || $PDF::root->{Prefs}->{ExtraParaSpacing} ),
		'Font' => $oFont,
		'Indent' => 0,
		'Leading' => &PDF::tellSize( $attr->{Leading} || $PDF::root->{Prefs}->{Leading} || $attr->{FontSize} || $PDF::root->{Prefs}->{FontSize} || 12 ),
		'Rotation' => $attr->{Rotation}? $attr->{Rotation} * 3.1416 / 180: 0,
		'Size' => &PDF::tellSize( $attr->{FontSize} || $PDF::root->{Prefs}->{FontSize} || 12 ),
		'Stream' => '',
		'TextDir' => $attr->{TextDir},	# 0: Normal, 1: 90 degree counterclockwise; 2: 90 degree clockwise; 3: upside-down
		'TextJustify' => ( $attr->{TextJustify} || $PDF::root->{Prefs}->{TextJustify} || 'Left' ),
		'VerticalAlign' => ( $attr->{VerticalAlign} || $PDF::root->{Prefs}->{VerticalAlign} || 'Top' ),
		'Voracious' => $attr->{Voracious},
		'WordSpacing' => ( $attr->{WordSpacing} || 0 ),
		'x' => 0,
		'y' => 0,
		'Filters' => [ ],
		'Dirty' => 0,
		'TracePos' => 0,
		'LeftX' => 0,
		'LeftY' => 0,
		'RightX' => 0,
		'RightY' => 0,
		'LastSpace' => 0,
		'ParaPos' => [ ],
		'XML' => [ @xmls ],
		'Text' => '',
		'IsCopy' => 0,
		'IsTemplate' => 0,
		'Name' => '',
		'ZIndex' => exists $attr->{ZIndex}? $attr->{ZIndex}: 0,
		'Encoding' => ( $attr->{Encoding} || 'WinAnsiEncoding' ),
	};
	bless $this, $class;
	$this->{LineBuffer} = {
		TextStart => 0,
		TextAlign => 'Left',
		TextLen   => 0,
		PDFCode   => '',
		NumTabs   => 0,
	};
	$this->{Resources} = new Resources( );
	if( defined $attr->{Color} ){	# For backward-compatibility.
		$attr->{FontColor} = $attr->{Color};
	}
	if( defined $attr->{FontColor} ){
			$this->{Color} = $attr->{FontColor};
	}
	for( qw(FontFace FontSize Leading FontColor BgColor BorderColor BorderWidth BorderDash TextJustify VerticalAlign ZIndex
		TextDir Rotation ContentPadding PaddingLeft PaddingRight FirstIndent BodyIndent IsContinued ExtraParaSpacing Encoding) ){
		if( defined $attr->{$_} ){ $this->{$_} = $attr->{$_}; }
		push( @{$this->{XML}}, qq{$_="$attr->{$_}"} ) if defined $attr->{$_};
	}
	for( qw(TextDir Rotation ContentPadding PaddingLeft PaddingRight FirstIndent BodyIndent IsContinued) ){
		$this->{$_} ||= 0;
	}
	if( defined $attr->{Texture} ){
		if( ref( $attr->{Texture} ) ne 'PDFTexture' ){
			$attr->{Texture} = &PDF::getObjByName( $attr->{Texture} );
		}
		push( @{$this->{XML}}, qq{Texture="$attr->{Texture}->{Name}"} );
	}
	if( defined $attr->{Shading} ){
		if( ref( $attr->{Shading} ) ne 'PDFShading' ){
			$attr->{Shading} = &PDF::getObjByName( $attr->{Shading} );
		}
		push( @{$this->{XML}}, qq{Shading="$attr->{Shading}->{Name}"} );
	}
	if( defined $attr->{Bookmark} ){
		my $t = new Outlines( $attr->{Bookmark}, { 'Fit'=>'FitR', 'Left'=>$parm->{Left}, 'Bottom'=>$parm->{Bottom}, 'Right'=>$parm->{Right}, 'Top'=>$parm->{Top} } );
		$this->{BookmarkName} = $t->getName( );
	}
	if( $TextContent::ContinuedPara || defined $attr->{IsContinued} && $attr->{IsContinued} ){
		$TextContent::ContinuedPara = 1;
		push( @{$this->{XML}}, qq{IsContinued="1"} );
	}
	for( qw(BodyIndent ContentPadding FirstIndent PaddingLeft PaddingRight) ){
		next unless( defined $attr->{$_} );
		$this->{$_} = &PDF::tellSize( $attr->{$_} );
	}
	$this->{TabPosition} = &PDF::tellSize( defined $attr->{TabPosition}? $attr->{TabPosition}: '1in' );
	my $UseGraph = 0;
	for( qw(BgColor BorderColor BorderWidth Texture Shading BorderDash) ){
		if( defined $attr->{$_} ){
			$UseGraph = 1;
			last;
		}
	}
	if( $UseGraph ){
		my $g = new GraphContent( ref( $parm ) eq 'Poly'? $PDF::root->getCurrPage( )->getArtBox( ):
			$parm, { 'InternalUse' => 1 } );
		$g->saveGState( );
		my $s = 0;	# Fill mode
		if( $attr->{BgColor} ){
			$g->setColor( $attr->{BgColor}, 1 );
			$s = 1;
		}
		if( $attr->{Texture} && ref( $attr->{Texture} ) eq 'PDFTexture' ){
			$g->setTexture( $attr->{Texture}, 1 );
			$s = 1;
		}
		if( $attr->{Shading} && ref( $attr->{Shading} ) eq 'PDFShading' ){
			my $r = new Rect( $parm );
			$g->gradFill( $attr->{Shading}, $r );
		}
		if( $attr->{BorderDash} ){
			$g->setDash( $attr->{BorderDash} );
			$attr->{BorderColor} ||= 'Black';
		}
		if( $attr->{BorderWidth} ){
			$g->setLineWidth( $attr->{BorderWidth} );
			$attr->{BorderColor} ||= 'Black';
		}
		if( $attr->{BorderColor} ){
			$g->setColor( $attr->{BorderColor} );
			$s = ( $s? 2: 0 );
		}
		if( ref( $parm ) eq 'Rect' ){
			$g->moveTo( 0, 0 );
			$g->drawRect( $parm->width( ), $parm->height( ), $s );
		} else {
			$g->drawPolyLine( $s, $parm->getPoints( ) );
		}
		$g->restoreGState( );
		$this->{Stream} = $g->{Stream};
		for my $res ( keys %{$g->{Resources}} ){
			for( keys %{$g->{Resources}->{$res}} ){
				$this->{Resources}->{$res}->{$_} = 1;
			}
		}
	}
	if( ref( $parm ) eq 'Rect' ){
		if( $this->{TextDir} ){
			if( $this->{TextDir} & 1 ){
				$parm->{Top} = $parm->{Bottom};
				$this->{Rotation} = 3.1416/2;
			}
			if( $this->{TextDir} & 2 ){
				$parm->{Left} = $parm->{Right};
				$this->{Rotation} = 3.1416/(-2);
			}
			if( $this->{TextDir} == 3 ){
				$this->{Rotation} = 3.1416;
				$parm->{Bottom} = $parm->{Top} - $parm->{Height};
				$parm->{Right} = $parm->{Left} + $parm->{Width};
			} else {
				$parm->{Bottom} = $parm->{Top} - $parm->{Width};
				$parm->{Right} = $parm->{Left} + $parm->{Height};
				( $parm->{Width}, $parm->{Height} ) = ( $parm->{Height}, $parm->{Width} );
			}
		}
		if( $this->{ContentPadding} ){
			$this->{Container}->shrink( $this->{ContentPadding} );
			if( $this->{TextDir} & 1 ){
				$this->{Container}->moveBy( 0, $this->{ContentPadding} * 2 );
			}
			if( $this->{TextDir} & 2 ){
				$this->{Container}->moveBy( -1 * $this->{ContentPadding} * 2, 0 );
			}
		}
	}
	if( exists $attr->{BlendMode} || exists $attr->{Opacity} ){
		my $gs = new ExtGState( );
		if( exists $attr->{BlendMode} ){
			$this->{BlendMode} = $attr->{BlendMode};
			$gs->setBlendMode( $attr->{BlendMode} );
		}
		if( exists $attr->{Opacity} ){	# 0 to 100, translated to 0 to 1 by the ExtGState object
			$this->{Opacity} = $attr->{Opacity};
			$gs->setOpacity( $attr->{Opacity} / 100 );
		}
		$this->{Stream} = qq{/$gs->{Name} gs } . $this->{Stream};
		$this->{Resources}->{ExtGState}->{ $gs->{Name} } = 1;
	}
	$this->{Stream} .= " BT $TextContent::endln";
	$this->setName( ref( $attr ) eq 'HASH' && $attr->{Name}? $attr->{Name}: '' );
	unless( ref( $attr ) eq 'HASH' && defined $attr->{InternalUse} && $attr->{InternalUse} ){
		$PDF::root->{CurrPage}->appendContent( $this );
		if( ref( $attr ) eq 'HASH' && $attr->{IsTemplate} ){
			$PDF::root->addToTemplate( $this );
		}
	}
	return $this;
}

sub getBookmark {
	return $PDF::root->getObjByName( shift->{BookmarkName} );
}

sub setFont {
	my( $this, $fontname, $size ) = @_;
	if( defined $fontname ){
		$this->{Font} = $PDF::root->getFont( $fontname, $this->{Encoding} );
	}
	if( $size ){
		$this->{Size} = $size;
	}
	$this->{LineBuffer}->{PDFCode} .= "/$this->{Font}->{Name} $this->{Size} Tf $TextContent::endln";
	$this->{Resources}->{Font}->{ $this->{Font}->{Name} } = 1;
}

sub setPos {
	my $this = shift;
	$this->{y} = $this->{Container}->top( ) - $this->{Leading};
	push( @TextContent::Ranges, $this->{Container}->getRange( $this->{y} ) );
	$this->{LineBuffer}->{TextStart} = $this->{x} = $TextContent::Ranges[0];
	my $cosval = cos( $this->{Rotation} );
	my $sinval = sin( $this->{Rotation} );
	$this->{LineBuffer}->{PDFCode} .= sprintf( "%.4f %.4f %.4f %.4f %.4f %.4f Tm $TextContent::endln %.4f %.4f Td $TextContent::endln",
		$cosval, $sinval, (-1) * $sinval, $cosval, $this->{Container}->topLeft( ), $this->{Container}->top( ), $TextContent::Ranges[0] - $this->{Container}->topLeft( ), (-1) * $this->{Leading} );
}

sub adjustStartPos {
	my( $this, $offx, $offy ) = @_;
	$this->{Stream} =~ s/Tm/Tm $offx $offy Td/;
	for( @{$this->{Annots}} ){
		$_->adjustStartPos( $offx, $offy );
	}
}

sub moveBy {
	my( $this, $offx, $offy ) = @_;
	return if( abs( $offx ) < 1e-5 && abs( $offy ) < 1e-5 );
	$offx = sprintf( "%.4f", $offx );
	$offy = sprintf( "%.4f", $offy );
	$this->{x} += $offx;
	$this->{Indent} += $offx;
	$offy = -1 * $offy;
	$this->{y} += $offy;
	$this->{LineBuffer}->{PDFCode} .= "$offx $offy Td ";
}

sub resetIndent {
	my $this = shift;
	$this->{x} -= $this->{Indent};
	if( abs( $this->{Indent} ) > 1e-5 ){
		$this->{LineBuffer}->{PDFCode} .= sprintf( "%.4f 0 Td ", -1 * $this->{Indent} );
	}
	$this->{Indent} = 0;
}

sub getPos {
	my $this = shift;
	return ( $this->{x}, $this->{y} );
}

sub setLeading {
	my( $this, $tl ) = @_;
	if( defined $tl ){
		$this->{LineBuffer}->{PDFCode} .= "$tl TL $TextContent::endln";
		$this->{Leading} = $tl;
	} else {
		$this->{LineBuffer}->{PDFCode} .= "$this->{Leading} TL $TextContent::endln";
	}
}

sub setWordSpacing {
	my( $this, $tw ) = @_;
	if( defined $tw ){
		$tw = eval( sprintf( "%.4f", $tw + $this->{WordSpacing} ) );
		$this->{LineBuffer}->{PDFCode} .= "$tw Tw $TextContent::endln";
	} else {
		$this->{LineBuffer}->{PDFCode} .= "$this->{WordSpacing} Tw $TextContent::endln";
	}
}

sub setCharSpacing {
	my( $this, $tc ) = @_;
	if( defined $tc ){
		$this->{LineBuffer}->{PDFCode} .= "$tc Tc $TextContent::endln";
		$this->{CharSpacing} = $tc;
	} else {
		$this->{LineBuffer}->{PDFCode} .= "$this->{CharSpacing} Tc $TextContent::endln";
	}
}

sub setColor {
	my( $this, $color ) = @_;
	if( defined $color ){
		$this->{Color} = $color;
	} else {
		$color = $this->{Color};
	}
	if( !defined $PDF::root->{Prefs}->{ColorSpace} || $PDF::root->{Prefs}->{ColorSpace} eq 'RGB' ){
		my ( $r, $g, $b ) = &Color::tellColor( $color );
		$this->{LineBuffer}->{PDFCode} .= "$r $g $b rg $TextContent::endln";
	} elsif( $PDF::root->{Prefs}->{ColorSpace} eq 'CMYK' ){
		my ( $c, $m, $y, $k ) = &Color::tellColor( $color );
		$this->{LineBuffer}->{PDFCode} .= "$c $m $y $k k $TextContent::endln";
	} elsif( $PDF::root->{Prefs}->{ColorSpace} eq 'Gray' ){
		my $g = &Color::tellColor( $color );
		$this->{LineBuffer}->{PDFCode} .= "$g g $TextContent::endln";
	}
}

sub setRenderMode {	# Left for historical reasons
	my( $this, $mode ) = @_;
	$this->{LineBuffer}->{PDFCode} .= qq{ $mode Tr };
}

sub addText {
	my( $this, $txt, $wid ) = @_;
	$txt = &PDF::escStr( $txt );
	$wid ||= 0;
	$this->{LineBuffer}->{PDFCode} .= "($txt) Tj $TextContent::endln";
	if( $this->{TracePos} ){
		( $this->{LeftX}, $this->{LeftY} ) = $this->getPos( );
	}
	$this->{x} += $wid;
	$this->{LineBuffer}->{TextLen} += $wid;
	if( $this->{TracePos} ){
		( $this->{RightX}, $this->{RightY} ) = $this->getPos( );
		if( $txt =~ /\s$/ ){
			$this->{RightX} -= $this->{LastSpace};
		}
	}
	$this->{Dirty} = 1;
}

sub newLine {
	my $this = shift;
	if( $this->{LineBuffer}->{TextAlign} eq 'Center' ){
		$this->{LineBuffer}->{PDFCode} = sprintf( "-%.4f 0 Td $this->{LineBuffer}->{PDFCode} %.4f 0 Td ",
			$this->{LineBuffer}->{TextLen} / 2, $this->{LineBuffer}->{TextLen} / 2 );
	} elsif( $this->{LineBuffer}->{TextAlign} eq 'Right' ){
		$this->{LineBuffer}->{PDFCode} = sprintf( "-%.4f 0 Td $this->{LineBuffer}->{PDFCode} %.4f 0 Td ",
			$this->{LineBuffer}->{TextLen}, $this->{LineBuffer}->{TextLen} );
	}
	$this->resetIndent( );
	$this->{Stream} .= $this->{LineBuffer}->{PDFCode};
	$this->{LineBuffer}->{PDFCode} = '';
	# If range is available, use next; otherwise find new ranges
	if( scalar @TextContent::Ranges ){
		@TextContent::LastRanges = splice( @TextContent::Ranges, 0, 2 );
	}
	unless( scalar @TextContent::Ranges > 1 ){
		$this->{Stream} .= "T* $TextContent::endln";
		$this->{y} -= $this->{Leading};
		push( @TextContent::Ranges, $this->{Container}->getRange( $this->{y} ) );
	}
	$this->{LineBuffer}->{TextStart} = $this->{x} = $TextContent::Ranges[0];
	$this->{LineBuffer}->{PDFCode} = '';
	$this->{LineBuffer}->{TextLen} = 0;
	$this->{LineBuffer}->{TextAlign} = 'Left';
	$this->{LineBuffer}->{NumTabs} = 0;
	if( abs( $TextContent::Ranges[0] - $TextContent::LastRanges[0] ) > 1e-5 ){
		$this->{Stream} .= sprintf( "%.4f 0 Td ", $TextContent::Ranges[0] - $TextContent::LastRanges[0] );
	}
	if( $this->{TracePos} && $this->{Dirty} ){
		my $rect = new Rect( $this->{LeftX}, $this->{LeftY}, $this->{RightX} - $this->{LastSpace}, $this->{RightY} );
		push( @$TextContent::AnnotBoxes, $rect );
		( $this->{LeftX}, $this->{LeftY} ) = $this->getPos( );
	}
}

sub visibleY {
	my $this = shift;
	my $y = $this->{y};
	if( $this->{Stream} =~ /Tj([^j]+)$/ ){
		my $chunk = $1;
		while( $chunk =~ /T\*/g ){
			$y += $this->{Leading};
		}
	}
	return $y;
}

sub verticalAlign {
	my $this = shift;
	my $offy = $this->{Container}->bottom( ) - $this->visibleY( );
	if( $this->{VerticalAlign} eq 'Bottom' ){
		$this->adjustStartPos( 0, eval( sprintf( "%.4f", $offy + 1 ) ) );	# Why add 1?
		for( @{$this->{ParaPos}} ){ $_->[1] += $offy + 1; }
	} elsif( $this->{VerticalAlign} eq 'Middle' ){
		$this->adjustStartPos( 0, eval( sprintf( "%.4f", $offy / 2 + 1 ) ) );
		for( @{$this->{ParaPos}} ){ $_->[1] += $offy / 2 + 1; }
	}
}

sub alignTo {
	my( $this, $x, $y, $justify ) = @_;
	return if( ref( $this->{Container} ) ne 'Rect' );
	my $BBox = $this->{Font}->{FontPtr}->{FontDescriptor}->{FontBBox};
	my $offx = $x - $this->{Container}->left( ) + $BBox->[0] / 1000;
	my $offy = $y - $this->{Container}->top( ) - $BBox->[1] / 1000 + $this->{Leading};
	if( $justify eq 'Right' ){
		$offx -= $this->{x} - $this->{Container}->left( ) - $this->{CharSpacing} - $this->{WordSpacing};
	} elsif( $justify eq 'Center' ){
		$offx -= ( $this->{x} - $this->{Container}->left( ) - $this->{CharSpacing} - $this->{WordSpacing} ) / 2;
	}
	$this->adjustStartPos( $offx, $offy );
}

sub saveStyle {
	my $this = shift;
	my %aStyle = map{ $_ => $this->{$_} } @TextContent::SaveAttribs;
	push( @TextContent::Styles, \%aStyle );
}

sub restoreStyle {
	my $this = shift;
	if( @TextContent::Styles ){
		my $aStyle = pop( @TextContent::Styles );
		map{ $this->{$_} = $aStyle->{$_}; } @TextContent::SaveAttribs;
	}
	$TextContent::pFont = $this->{Font};
}

sub finishUp {
	my $this = shift;
	$this->{Stream} .= $this->{LineBuffer}->{PDFCode};
	$this->{LineBuffer}->{PDFCode} = '';
	unless( ref( $this->{Container} ) ne 'Rect' ){
		$this->verticalAlign( );
		if( $this->{TextDir} ){
			for( @{$this->{Annots}} ){
				$_->flip( $this->{Container}, $this->{TextDir} );
			}
		}
		if( $this->{ContentPadding} ){
			if( $this->{TextDir} & 1 ){
				$this->{Container}->moveBy( 0, -1 * $this->{ContentPadding} * 2 );
			}
			if( $this->{TextDir} & 2 ){
				$this->{Container}->moveBy( $this->{ContentPadding} * 2, 0 );
			}
			$this->{Container}->shrink( $this->{ContentPadding} * (-1) );
		}
	}
	$this->{Stream} .= "${TextContent::endln} ET ${TextContent::endln}";
	$this->{Text} =~ s/\a//g;
	return unless( $this->{TextDir} || $this->{Rotation} );
	for my $p ( @{$this->{ParaPos}} ){
		my( $a, $b ) = @$p;
		if( $this->{TextDir} == 1 ){
			$p->[0] = $this->{Container}->top( ) - $b + $this->{Container}->left( );
			$p->[1] = $this->{Container}->top( ) + $a - $this->{Container}->left( );
		} elsif( $this->{TextDir} == 2 ){
			$p->[0] = $this->{Container}->left( ) + $b - $this->{Container}->top( );
			$p->[1] = $this->{Container}->left( ) - $a + $this->{Container}->top( );
		} elsif( $this->{TextDir} == 3 ){
			$p->[0] = $this->{Container}->left( ) * 2 - $a;
			$p->[1] = $this->{Container}->top( ) * 2 - $b;
		} else {
			my $t1 = ( $this->{Container}->top( ) - $b ) * sin( $this->{Rotation} / 2 ) * 2;
			my $t2 = $this->{Container}->left( ) - $a;
			$p->[0] = $this->{Container}->left( ) + $t1 * cos( $this->{Rotation} / 2 ) - $t2 * cos( $this->{Rotation} );
			$p->[1] += $t1 * sin( $this->{Rotation} / 2 ) - $t2 * sin( $this->{Rotation} );
		}
	}
}

sub importText {
	my $this = shift;
	@TextContent::Ranges = ( );
	$this->restoreStyle( ) if( $TextContent::InStyle );
	my( $pSize, $pWord );
	$TextContent::pFont = $this->{Font};
	$pSize = $this->{Size};
	$this->setPos( );
	$this->setLeading( );
	$this->setColor( );
	$this->setFont( );
	$this->setWordSpacing( );
	$this->setCharSpacing( );
	my( $i, $j, $k ) = ( 0 ) x 3;
	my @Words = ( );
	while( @TextContent::Paragraphs ){
		map { push( @Words, [$_] ); } split( /\s+/, shift( @TextContent::Paragraphs ) );
		push( @{$this->{ParaPos}}, [ $this->getPos( ) ] );
		$i = $k = 0;
		# Each of the @Words array is an anonymous hash of three elements: word itself, pixel length of the chars, and pixel length of the space.
		foreach my $pWord ( @Words ){
			$i++;
			if( $pWord->[0] =~ /^\a\^(.*)$/ ){
				$k++;
				$pWord->[1] = 0; $pWord->[2] = 0;
				if( { 'b'=>1, 'i'=>1, 'bi'=>1, 'ib'=>1 }->{$1} ){
					my $ptr = $TextContent::pFont;
					$TextContent::pFont = $PDF::root->getFont( { 'b'=>$ptr->{Bold}, 'i'=>$ptr->{Italic}, 'bi'=>$ptr->{BoldItalic}, 'ib'=>$ptr->{BoldItalic} }->{$1}, $this->{Encoding} );
				} elsif( { 'B'=>1, 'I'=>1, 'BI'=>1, 'IB'=>1 }->{$1} ){
					$TextContent::pFont = $this->{Font};
				} elsif( $1 =~ /^f:(.*)/ ){
					my @attribs = split( /&/, $1 );
					my %flds = ( );
					foreach( @attribs ){
						my( $key, $val ) = split( /=/ );
						$flds{ ucfirst(lc($key)) } = $val;
					}
					if( defined $flds{Size} ){
						$pSize = $flds{Size};
					}
					if( defined $flds{Face} ){
						$this->{Font} = $PDF::root->getFont( $fld{Face}, $this->{Encoding} );
						$TextContent::pFont = $this->{Font};
					}
				} elsif( $1 eq 'F' ){
					if( @TextContent::Styles ){
						$pSize = $TextContent::Styles[-1]->{Size};
						$TextContent::pFont = $TextContent::Styles[-1]->{Font};
					} else {
						$pSize = $this->{Size};
						$TextContent::pFont = $this->{Font};
					}
				} elsif( $1 eq 'C' ){
					last;
				}
				next;
			}
			$pWord->[1] = $TextContent::pFont->getWordWidth( $pWord->[0], $pSize );
			$pWord->[2] = $TextContent::pFont->getCharWidth( ' ' ) * $pSize / 1000 + $this->{CharSpacing} + $this->{WordSpacing};
			if( $pWord->[0] =~ /^[,\.:;]/ ){
				$Words[$i - $k - 1]->[2] = 0;
			}
			$k = 0;
		}
		$TextContent::pFont = $this->{Font};
		my $FirstLine = !$TextContent::ContinuedPara;
		$TextContent::ContinuedPara = 0;
		while( @Words ){
			my $ThisLineLen = 0;
			my $indentoffset = { 'Uniform'=>1, 'Left'=>1 }->{$this->{TextJustify}}?
				( $FirstLine? $this->{FirstIndent}: $this->{BodyIndent} ): 0;
			$this->moveBy( $indentoffset + $this->{PaddingLeft}, 0 );
			$ThisLineLen = $indentoffset + $this->{PaddingLeft};
			$i = 0;
			$j = 0;
			$ThisLineLen += $Words[0]->[1];
			my $AvailWidth = $TextContent::Ranges[1] - $TextContent::Ranges[0] - $this->{PaddingRight};
			while( $i < $#Words && ( $ThisLineLen + $Words[$i]->[2] + $Words[$i+1]->[1] <= $AvailWidth ) ){
				if( $Words[$i]->[2] ){
					$j++;
				} elsif( $Words[$i]->[0] eq "\a^n" ){
					last;
				}
				$ThisLineLen += $Words[$i]->[2] + $Words[$i+1]->[1];
				$i++;
			}
			my @TheseWords = splice( @Words, 0, $i+1 );
			$k = $#TheseWords;
			while( $k && $TheseWords[$k]->[0] =~ /^\a/ ){ $k--; }
			$TheseWords[$k]->[2] = 0;
			my $WordSpacing = 0;
			$j -= ( $#TheseWords - $k );
			if( $this->{TextJustify} eq 'Uniform' && $j ){
				$WordSpacing = @Words? ( $AvailWidth - $ThisLineLen ) / $j: 0;
				$this->setWordSpacing( $WordSpacing );
			} elsif( $this->{TextJustify} eq 'Center' ){
				$this->setWordSpacing( );
				$this->moveBy( ( $AvailWidth - $ThisLineLen ) / 2, 0 );
				if( $FirstLine ){ ${$this->{ParaPos}}[-1]->[0] += ( $AvailWidth - $ThisLineLen ) / 2; }
			} elsif( $this->{TextJustify} eq 'Right' ){
				$this->setWordSpacing( );
				$this->moveBy( $AvailWidth - $ThisLineLen, 0 );
				if( $FirstLine ){ ${$this->{ParaPos}}[-1]->[0] += $AvailWidth - $ThisLineLen; }
			} else {
				$this->setWordSpacing( );
			}
			my $cache = '';
			my $cachelen = 0;
			for $i ( 0..$#TheseWords ){
				$this->{Text} .= "$TheseWords[$i]->[0] ";	# Used when exporting XML
				if( $TheseWords[$i]->[0] =~ /^\a\^(.*)$/ ){
					my $Code = $1;
					$this->addText( $cache, $cachelen ) if( length( $cache ) );
					$cache = '';
					$cachelen = 0;
					if( { 'b'=>1, 'i'=>1, 'bi'=>1, 'ib'=>1 }->{$Code} ){
						$this->saveStyle( );
						my $ptr = $TextContent::pFont->{FontPtr};
						$this->setFont( { 'b'=>$ptr->{Bold}, 'i'=>$ptr->{Italic}, 'bi'=>$ptr->{BoldItalic}, 'ib'=>$ptr->{BoldItalic} }->{$Code} );
					} elsif( { 'B'=>1, 'I'=>1, 'BI'=>1, 'IB'=>1 }->{$Code} ){
						$this->restoreStyle( );
						$this->setFont( );
					} elsif( $Code eq 'r' || $Code eq 'e' && ( !$this->{Rotation} || $this->{TextDir} ) ){
						$this->{TracePos} = 1;
						$this->{Dirty} = 0;
						$TextContent::InStyle = 1;
						$this->saveStyle( );
						$this->setColor( 'Blue' );
					} elsif( $Code eq 'R' || $Code eq 'E' ){
						$TextContent::InStyle = 0;
						$this->restoreStyle( );
						$this->setColor( );
						$this->{TracePos} = 0;
						$this->{Dirty} = 0;
						$i--;
						if( !$this->{Rotation} || $this->{TextDir} ){
							$Code eq 'E' && substr( $TheseWords[$i]->[0], 0, 0, 'mailto:' );
							push( @$TextContent::AnnotBoxes, new Rect( $this->{LeftX}, $this->{LeftY}, $this->{RightX}, $this->{RightY} ) );
							while( @$TextContent::AnnotBoxes ){
								my $rect = shift( @$TextContent::AnnotBoxes );
								$rect->{Bottom} += $TextContent::pFont->{FontPtr}->{FontDescriptor}->{Descent} * $this->{Size} / 1000;
								$rect->height( $this->{Size} );
								push( @{$this->{Annots}}, new Annot( $rect, 'Link', { 'URI' => $TheseWords[$i]->[0], 'Auto' => 1 } ) );
							}
						}
					} elsif( $Code eq 'C' ){
						$this->addText( $cache, $cachelen ) if( length( $cache ) );
						unshift( @Words, @TheseWords[$i+1..$#TheseWords] ) if( $i < $#TheseWords );
						unshift( @TextContent::Paragraphs, join( ' ', map{ $_->[0] } @Words ) ) if( @Words );
						$this->saveStyle( ) if( $TextContent::InStyle );
						$this->finishUp( );
						return 0;
					} elsif( $Code =~ /^[uUsShHL]:?(.*)/ && ( !$this->{Rotation} || $this->{TextDir} ) ){
						$this->{Dirty} = 0;
						my @attribs = split( /&/, $1 );
						my %flds = ( );
						foreach( @attribs ){
							my( $key, $val ) = split( /=/ );
							$flds{ ucfirst(lc($key)) } = $val;
						}
						$Code = substr( $Code, 0, 1 );
						if( $Code ne uc( $Code ) ){
							$this->{TracePos} = 1;
						} else {
							$this->{TracePos} = 0;
							my $annotattr = { 'Color' => ( $flds{Color} || ( $Code eq 'H'? 'Yellow': $this->{Color} ), 'Auto' => 1 ) };
							$annotattr->{Width} = $this->{Size} / 12;
							if( $flds{Width} ){	$annotattr->{Width} = $flds{Width}; }
							if( $flds{Dash} ){	$annotattr->{Dash} = $flds{Dash}; }
							if( $Code eq 'L' ){
								my $oAnnot = new Annot( new Rect( $TextContent::Ranges[0], $this->{y} + $this->{Leading} / 2, $TextContent::Ranges[1], $this->{y} + $this->{Leading} / 2 ), 'Line', $annotattr );
								push( @{$this->{Annots}}, $oAnnot );
							} else {
								push( @$TextContent::AnnotBoxes, new Rect( $this->{LeftX}, $this->{LeftY}, $this->{RightX}, $this->{RightY} ) );
								while( @$TextContent::AnnotBoxes ){
									my $rect = shift( @$TextContent::AnnotBoxes );
									$rect->{Bottom} += $TextContent::pFont->{FontPtr}->{FontDescriptor}->{Descent} * $this->{Size} / 1000;
									$rect->height( $this->{Size} );
									push( @{$this->{Annots}}, new Annot( $rect, {'U'=>'Underline', 'S'=>'StrikeOut', 'H'=>'Highlight'}->{ $Code }, $annotattr ) );
								}
							}
						}
					} elsif( $Code =~ /^f:(.*)/ ){
						$TextContent::InStyle = 1;
						$this->saveStyle( );
						my @attribs = split( /&/, $1 );
						my %flds = ( );
						foreach( @attribs ){
							my( $key, $val ) = split( /=/ );
							$flds{ ucfirst(lc($key)) } = $val;
						}
						if( defined $flds{Size} ){
							$this->setFont( undef, $flds{Size} );
							push( @TextContent::ChangedAttribs, 'Size' );
						}
						if( defined $flds{Face} ){
							$this->setFont( $flds{Face}, $this->{Size} );
							push( @TextContent::ChangedAttribs, 'Face' );
						}
						if( defined $flds{Color} ){
							$this->setColor( $flds{Color} );
							push( @TextContent::ChangedAttribs, 'Color' );
						}
						if( defined $flds{Leading} ){
							$this->setLeading( $flds{Leading} );
							push( @TextContent::ChangedAttribs, 'Leading' );
						}
						$TextContent::pFont = $this->{Font};
					} elsif( $Code eq 'F' ){
						$TextContent::InStyle = 0;
						$this->restoreStyle( );
						my %attribs = map{ $_ => 1 } @TextContent::ChangedAttribs;
						$this->setFont( ) if( $attribs{Face} || $attribs{Size} );
						$this->setColor( $this->{Color} ) if( $attribs{Color} );
						@TextContent::ChangedAttribs = ( );
					} elsif( $Code =~ /^a:(.*)/ ){
						my @attribs = split( /&/, $1 );
						my %flds = ( );
						foreach( @attribs ){
							my( $key, $val ) = split( /=/ );
							$flds{ ucfirst(lc($key)) } = $val;
						}
						$TextContent::InStyle = 1;
						$this->saveStyle( );
						if( defined $flds{Vert} ){ $this->{VerticalAlign} = $flds{Vert}; }
						if( defined $flds{Align} ){ $this->{TextJustify} = $flds{Align}; }
					} elsif( $Code eq 'A' ){
						$TextContent::InStyle = 0;
						$this->restoreStyle( );
					} elsif( $Code =~ /^t:?(.*)/ ){
						my @attribs = split( /&/, $1 );
						my %flds = ( );
						foreach( @attribs ){
							my( $key, $val ) = split( /=/ );
							$flds{ ucfirst(lc($key)) } = $val;
						}
						my( $x, $y ) = $this->getPos( );
						$this->{x} -= $this->{LastSpace};	# Do not take the trailing space into consideration
						$this->{LineBuffer}->{TextLen} -= $this->{LastSpace};
						if( $this->{LineBuffer}->{TextAlign} eq 'Center' ){
							$this->{LineBuffer}->{PDFCode} = sprintf( "-%.4f 0 Td $this->{LineBuffer}->{PDFCode} %.4f 0 Td ",
								$this->{LineBuffer}->{TextLen} / 2, $this->{LineBuffer}->{TextLen} / 2 );
						} elsif( $this->{LineBuffer}->{TextAlign} eq 'Right' ){
							$this->{LineBuffer}->{PDFCode} = sprintf( "-%.4f 0 Td $this->{LineBuffer}->{PDFCode} %.4f 0 Td ",
								$this->{LineBuffer}->{TextLen}, $this->{LineBuffer}->{TextLen} );
						}
						$this->{Stream} .= $this->{LineBuffer}->{PDFCode};
						$this->{LineBuffer}->{PDFCode} = '';
						$this->{LineBuffer}->{TextLen} = 0;
						$this->{LineBuffer}->{TextAlign} = 'Left';
						my $offx;
						if( defined $flds{Align} ){
							$this->{LineBuffer}->{TextAlign} = $flds{Align};
						}
						if( defined $flds{Pos} ){
							$offx = &PDF::tellSize( $flds{Pos} );
							$this->resetIndent( );
							$this->moveBy( $offx, 0 );
						} else {
							my $num = int( ( $x - $this->{LineBuffer}->{TextStart} ) / $this->{TabPosition} ) + 1;
							$this->{LineBuffer}->{NumTabs}++;
							if( $this->{LineBuffer}->{NumTabs} == 1 ){
								$this->resetIndent( );
								$offx = $num * $this->{TabPosition} - $this->{Indent};
							} else {
								$offx = $num * $this->{TabPosition};
							}
							$this->moveBy( $offx, 0 );
						}
						$this->{LineBuffer}->{TextStart} = $this->{x};	# Current text start position.
					} elsif( $Code eq 'n' ){
						$this->addText( $cache, $cachelen ) if( length( $cache ) );
						unshift( @Words, splice( @TheseWords, $i+1 ) ) if( $i < $#TheseWords );
						last;
					}
					next;
				} else {
					$cache .= $TheseWords[$i]->[0];
					if( $TheseWords[$i]->[2] ){
						$cache .= ' ';
					}
					$this->{LastSpace} = $TheseWords[$i]->[2] + $WordSpacing;
					$cachelen += $TheseWords[$i]->[1] + $this->{LastSpace};
				}
			}
			$this->addText( $cache, $cachelen ) if( length( $cache ) );
			$this->newLine( ) if( @Words || $this->{ExtraParaSpacing} );
			if( $FirstLine && $this->{FirstIndent} ||
				!$FirstLine && $this->{BodyIndent} ||
				$this->{PaddingLeft} ){
				$this->resetIndent( );
			}
			if( $FirstLine ){ $FirstLine = 0; }
			if( !$this->{Voracious} && $this->{y} <= $this->{Container}->bottom( ) ){
				unshift( @TextContent::Paragraphs, join( ' ', map{ $_->[0] } @Words ) );
				$TextContent::ContinuedPara = 1;
				$this->saveStyle( ) if( $TextContent::InStyle );
				$this->finishUp( );
				return 0;
			}
		}
		$this->newLine( );
		$this->resetIndent( );
		if( !$this->{Voracious} && $this->{y} <= $this->{Container}->bottom( ) ){
			unshift( @TextContent::Paragraphs, join( ' ', map{ $_->[0] } @Words ) );
			$TextContent::ContinuedPara = 1;
			$this->verticalAlign( );
			$this->saveStyle( ) if( $TextContent::InStyle );
			$this->finishUp( );
			return 0;
		}
		$this->{Text} .= "\n\n";
	}
	$this->finishUp( );
	return 1;
}

sub getParaPos {
	my( $this, $img, $offset ) = @_;
	my( $x, $y ) = ( $offset + $img->{DisplayWidth} / 2, ( $img->{DisplayHeight} - $this->{Size} ) / 2 );
	for( @{$this->{ParaPos}} ){
		if( !$this->{TextDir} && !$this->{Rotation} ){
			$_->[0] -= $x;
			$_->[1] -= $y;
		} elsif( $this->{TextDir} == 1 ){
			$_->[0] += $y;
			$_->[1] -= $x;
		} elsif( $this->{TextDir} == 2 ){
			$_->[0] -= $y;
			$_->[1] += $x;
		} elsif( $this->{TextDir} == 3 ){
			$_->[0] += $x;
			$_->[1] += $y;
		} else {	# Rotated text
			$_->[0] -= $x * cos( $this->{Rotation} );
			$_->[1] -= $y * cos( $this->{Rotation} ) + $x * sin( $this->{Rotation} );
		}
	}
	return @{$this->{ParaPos}};
}

sub startXML {
	my( $this, $dep ) = @_;
	# If the object is created from a template, AND it isn't a TextContent, which means the
	# content is copied, too, then there's no need to generate output.
	if( ref( $this ) ne 'TextContent' ){
		return if( $this->{IsCopy} );
		push( @{$this->{XML}}, qq{IsTemplate="1"} ) if( $this->{IsTemplate} );
	}
	$this->{Text} =~ s/(\^[Cp]|\s)+$//;		# Remove redundant column-change signs.
	$this->{Text} =~ s/]]>/]] >/g;			# Text will be shown in CDATA segments.
	$this->{Text} =~ s/\^[rReE]\s*//g;		# Remove the marks inserted for a URI.
	$this->{Text} =~ s{([\x80-\xFF]+)}{']]>' . join( '', map { join( '', '&#x', uc( unpack( 'H*', $_ ) ), ';' ) } split( //, $1 ) ) . '<![CDATA[' }ge;
	print "\t" x $dep, '<Text ', join( ' ', qq{Name="$this->{Name}"}, @{$this->{XML}} ), '><![CDATA[', $this->{Text}, ']]>';
}

sub endXML {
	my( $this, $dep ) = @_;
	return if( $this->{IsCopy} && ref( $this ) ne 'TextContent' );
	print "</Text>\n";
}

sub finalize {
	my $this = shift;
	$this->SUPER::finalize( );
	undef $this->{Resources};
	@{$this->{Annots}} = ( );
}

# $txt is the reference to a chunk of text
sub reformatText {
	my( $this, $txt, $arrayref ) = @_;
	$arrayref ||= \@TextContent::Paragraphs;
	$$txt =~ s/(?<!\\)\^(\S+)/ \a^$1 /g;
	$$txt =~ s/[\n\r]{4,}|\n{2,}/ \a^p /g;
	$$txt =~ s/[\n\r]+/ /g;
	if( exists $PDF::root->{Prefs}->{FindBIU} && $PDF::root->{Prefs}->{FindBIU} ){
		$$txt =~ s/(?<!\S)\*+([^\s\*]+)\*+/ \a^b $1 \a^B /g;
		$$txt =~ s/(?<!\S)_+([^\s_]+)_+/ \a^u $1 \a^U /g;
		$$txt =~ s/(?<!\S)=+([^\s-]+)=+/ \a^i $1 \a^I /g;
	}
	if( exists $PDF::root->{Prefs}->{FindHyperlink} && $PDF::root->{Prefs}->{FindHyperlink} ){
		$$txt =~ s{[^\(\)<>@,;:\\\[\]\s]+\@[^\(\)<>@,;:\\\[\]\s]+}{ \a^e $& \a^E }g;
		$$txt =~ s{((https?)|(ftp))://([^\s,"\(\)\[\]<>])+}{ \a^r $& \a^R }gi;
	}
	if( exists $PDF::root->{Prefs}->{ReplaceEntities} && $PDF::root->{Prefs}->{ReplaceEntities} ){
		my $CharTable = \%PDFFont::WinAnsiChars;
		if( $PDF::root->{Prefs}->{Encoding} eq 'PDFDocEncoding' ){ $CharTable = \%PDFFont::PDFDocChars; }
		elsif( $PDF::root->{Prefs}->{Encoding} eq 'MacRomanEncoding' ){ $CharTable = \%PDFFont::MacRomanChars; }
		elsif( $PDF::root->{Prefs}->{Encoding} eq 'StandardEncoding' ){ $CharTable = \%PDFFont::StandardChars; }
		$$txt =~ s/(?<!\\)&(\w+);/chr($CharTable->{$1})/ge;
	}
	@$arrayref = split( / \a\^p/, $$txt );
	undef $$txt;
	map { s/(^\s+)|(\s+$)//; } @$arrayref;
}

1;
