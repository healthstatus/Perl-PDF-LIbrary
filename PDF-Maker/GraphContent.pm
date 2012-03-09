#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package GraphContent;

@GraphContent::ISA = qw(PDFStream);
use FileHandle;

use Carp;
use Annot;
use PDFFont;
use Outlines;
use Shape;
use XML::Parser;

$GraphContent::endln = "\x0D\x0A";

%GraphContent::LineCapStyle = (
	'Butt' => 0,
	'Round' => 1,
	'Square' => 2,
);

%GraphContent::LineJoinStyle = (
	'Miter' => 0,
	'Round' => 1,
	'Bevel' => 2,
);

%GraphContent::DashPatterns = (
	'Solid' => '[ ] 0',
	'Dotted' => '[2] 0',
	'Dashed' => '[5 2] 0',
	'DashDot' => '[8 2 2 2] 0',
);

sub new {
	my( $class, $parm, $attr ) = @_;
	if( ref( $parm ) eq $class ){		# Copy constructing
		my $this = {
			'Stream' => $parm->{Stream},
			'Container' => $parm->{Container},
			'XML' => $parm->{XML},		# Note this is a reference to array
			'CallStack' => [ ],
			'IsCopy' => 1,				# Indicate it is created from template
			'IsTemplate' => 0,
			'x' => 0,
			'y' => 0,
			'Name' => '',
			'Resources' => new Resources( $parm->{Resources} ),
			'Tagged' => $parm->{Tagged},	# New in version 3 (May 2002) to mark the object
			'ZIndex' => ( defined $attr && ref( $attr ) eq 'HASH' && exists $attr->{ZIndex} )? $attr->{ZIndex}: 0,
		};
		bless $this, $class;
		$this->setName( defined $attr && ref( $attr ) eq 'HASH'? $attr->{Name}: '' );
		$PDF::root->{CurrPage}->appendContent( $this );
		return $this;
	}	
	unless( ref( $parm ) eq 'Rect' || ref( $parm ) eq 'Poly' ){	# oContainer is omittable
		$attr = $parm;					# Assume it is a hash
		$parm = $PDF::root->getCurrPage( )->getArtBox( );
	}
	my $this = {
		'Stream' => '',
		'Container' => $parm,
		'Filters' => [ ],
		'x' => ( $parm->left( ) || 0 ),
		'y' => ( $parm->bottom( ) || 0 ),
		'XML' => [ ],
		'CallStack' => [ ],
		'IsCopy' => 0,
		'IsTemplate' => 0,
		'Name' => '',
		'Resources' => new Resources( ),
		'Tagged' => ( exists $attr->{Tagged} && $attr->{Tagged} )? 1: 0,
		'ZIndex' => exists $attr->{ZIndex}? $attr->{ZIndex}: 0,
	};
	bless $this, $class;
	unless( ref( $attr ) eq 'HASH' && ( exists $attr->{InternalUse} && $attr->{InternalUse} || exists $attr->{NoAppend} && $attr->{NoAppend} ) ){
		# Internal use: This object is temporarily used by another object, which will make use of the stream data.
		# No append: The Field and Annot object will make an Appearance (subclass of GraphContent) and take care of the linkage.
		$this->setName( $attr->{Name} );
		$PDF::root->{CurrPage}->appendContent( $this );
		if( exists $attr->{IsTemplate} && $attr->{IsTemplate} ){
			&PDF::addToTemplate( $this );
		}
	}
	return $this unless( ref( $attr ) eq 'HASH' );
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
		$this->{Stream} .= qq{/$gs->{Name} gs };
		$this->{Resources}->{ExtGState}->{ $gs->{Name} } = 1;
	}
	if( exists $attr->{Bookmark} ){
		my $t = new Outlines( $attr->{Bookmark}, { 'Fit'=>'FitR', 'Left'=>$parm->{Left}, 'Bottom'=>$parm->{Bottom}, 'Right'=>$parm->{Right}, 'Top'=>$parm->{Top} } );
		$this->{BookmarkName} = $t->getName( );
	}
	return $this;
}

#======================== Positioning ============================

# Set current position AND begin a new graph state
sub setPos {
	my( $this, $x, $y ) = @_;
	$this->restoreGState( );
	$this->saveGState( );
	$this->moveTo( $x, $y );
}

# Get current position in RELATIVE coordinates
sub getPos {
	my $this = shift;
	return ( $this->{x} - $this->{Container}->left( ), $this->{y} - $this->{Container}->bottom( ) );
}

# Set current position only
sub moveTo {
	my( $this, $x, $y, $nocode ) = @_;
	push( @{$this->{XML}}, qq{<MoveTo X="$x" Y="$y" />} ) unless( @{$this->{CallStack}} );
	$x = &PDF::tellSize( $x || 0 );
	$y = &PDF::tellSize( $y || 0 );
	$this->{x} = $this->{Container}->left( ) + $x;
	$this->{y} = $this->{Container}->bottom( ) + $y;
	unless( $nocode ){
		$this->{Stream} .= sprintf( "%.4f %.4f m $GraphContent::endln", $this->{x}, $this->{y} );
	}
}

# Move current position by offsets
sub moveBy {
	my( $this, $offx, $offy ) = @_;
	push( @{$this->{XML}}, qq{<MoveTo OffX="$offx" OffY="$offy" />} ) unless( @{$this->{CallStack}} );
	$offx = &PDF::tellSize( $offx );
	$offy = &PDF::tellSize( $offy );
	$this->{x} += $offx;
	$this->{y} += $offy;
	$this->{Stream} .= sprintf( "%.4f %.4f m $GraphContent::endln", $this->{x}, $this->{y} );
}

#===================== Setting Parameters ========================

# Set line width
sub setLineWidth {
	my( $this, $width ) = @_;
	push( @{$this->{XML}}, qq{<Set LineWidth="$width" />} ) unless( @{$this->{CallStack}} );
	$width = &PDF::tellSize( $width );
	$this->{Stream} .= "$width w $GraphContent::endln";
}

# Set line cap style. $cap can be either a number or a name: Butt, Round, Square
sub setLineCap {
	my( $this, $cap ) = @_;
	push( @{$this->{XML}}, qq{<Set LineCap="$cap" />} ) unless( @{$this->{CallStack}} );
	if( defined $GraphContent::LineCapStyle{$cap} ){
		$cap = $GraphContent::LineCapStyle{$cap};
	} else {
		$cap %= 3;
	}
	$this->{Stream} .= "$cap J $GraphContent::endln";
}

# Set line join style. $lj can be either a number or a name: Miter, Round, Bevel
sub setLineJoin {
	my( $this, $lj ) = @_;
	push( @{$this->{XML}}, qq{<Set LineJoin="$lj" />} ) unless( @{$this->{CallStack}} );
	if( defined $GraphContent::LineJoinStyle{$lj} ){
		$lj = $GraphContent::LineJoinStyle{$lj};
	} else {
		$lj %= 3;
	}
	$this->{Stream} .= "$lj j $GraphContent::endln";
}

# Set line join miter limit for miter style
sub setMiterLimit {
	my( $this, $ml ) = @_;
	push( @{$this->{XML}}, qq{<Set MiterLimit="$ml" />} ) unless( @{$this->{CallStack}} );
	$this->{Stream} .= "$ml M $GraphContent::endln";
}

# Set color for stroke (ground=0) or fill (ground=1) operation. 'RRGGBB' or standard color names
sub setColor {
	my( $this, $color, $ground, $space ) = @_;
	$ground ||= '';
	$space ||= '';
	push( @{$this->{XML}}, qq{<Set Color="$color" Ground="$ground" ColorSpace="$space" />} ) unless( @{$this->{CallStack}} );
	$space ||= defined $PDF::root->{Prefs}->{ColorSpace}? $PDF::root->{Prefs}->{ColorSpace}: 'RGB';
	if( $space eq 'CMYK' ){
		my ( $c, $m, $y, $k ) = &Color::tellColor( $color, $space );
		my $gs = ( $ground? 'k': 'K' );
		$this->{Stream} .= "$c $m $y $k $gs $GraphContent::endln";
	} elsif( $space eq 'Gray' ){
		my $g = &Color::tellColor( $color, $space );
		my $gs = ( $ground? 'g': 'G' );
		$this->{Stream} .= "$g $gs $GraphContent::endln";
	} else {
		my ( $r, $g, $b ) = &Color::tellColor( $color, $space );
		my $gs = ( $ground? 'rg': 'RG' );
		$this->{Stream} .= "$r $g $b $gs $GraphContent::endln";
	}
}

# Set color in grayscale. If color is non-zero digit, set as 256-grade gray color. Otherwise treat it as color names and convert to gray.
sub setGrayColor {
	my( $this, $color, $ground ) = @_;
	push( @{$this->{XML}}, qq{<Set Color="$color" Ground="$ground" ColorSpace="Gray" />} ) unless( @{$this->{CallStack}} );
	if( $color != 0 ){	# If it is a color name, it is equal to zero.
		$this->{Stream} .= sprintf( "%.3f %s ", $color % 256 / 255, ( $ground? 'g': 'G' ) );
	} else {
		$this->setColor( $color, $ground, 'Gray' );
	}
}

# Set line dash pattern, which can be one of the following formats:
#	1. Standard PDF format, such as "[2 3] 4"
#	2. Comprised of 0's and 1's such as '011000' for the same pattern -- 1 means solid pixel and 0 means gap
#	3. One of the predefined dash pattern names: Solid, Dotted, Dashed, DashDot
sub setDash {
	my( $this, $dash, $returnonly ) = @_;
	unless( $returnonly || @{$this->{CallStack}} ){
		push( @{$this->{XML}}, qq{<Set Dash="$dash" />} ) unless( @{$this->{CallStack}} );
	}
	if( defined $GraphContent::DashPatterns{$dash} ){
		$dash = $GraphContent::DashPatterns{$dash};
	} elsif( $dash =~ /^[01]+$/ ){
		my @secs = ( );
		while( $dash =~ /(.)\1*/g ){
			push( @secs, length($&) );
		}
		my $pre = 0;
		$#secs == 0 && undef @secs;
		if( $#secs > 1 && ! ( $#secs % 2 ) ){
			$pre = shift( @secs );
			if( $dash =~ /^1/ ){
				push( @secs, shift @secs );
			} else {
				$pre *= -1;
				map{ $pre += $_; } @secs;
			}
		}
		$#secs == 1 && $secs[1] == $secs[0] && pop( @secs );
		$dash = '[' . join( ' ', @secs ) . qq{] $pre};
	}
	if( $returnonly ){ # Internally used by Field.pm; the phase digit should be removed
		chop( $dash );
		return $dash;
	} else {
		$this->{Stream} .= "$dash d $GraphContent::endln";
	}
}

# Set current color space, which could be RGB, Gray, or CMYK
sub setColorSpace {
	my( $this, $cs ) = @_;
	push( @{$this->{XML}}, qq{<Set ColorSpace="$cs" />} ) unless( @{$this->{CallStack}} );
	$this->{Stream} .= qq{/$cs cs };
}

# Set texture as if setting a color. $pat must be a PDFTexture object
sub setTexture {
	my( $this, $pat, $ground, $color ) = @_;
	my $cs = 'Pattern';
	$ground ||= 0;
	if( ref($pat) ne 'PDFTexture' ){
		croak "setTexture: Parameter is not a PDFTexture object in calling this function";
	}
	unless( @{$this->{CallStack}} ){
		my @xml = ( qq{Texture="$pat->{Name}"} );
		$ground && push( @xml, qq{Ground="1"} );
		defined $color && push( @xml, qq{Color="$color"} );
		push( @{$this->{XML}}, join( ' ', '<Set', @xml, '/>' ) );
	}
	if( $pat->{PaintType} == 2 ){
		$color = join( ' ', &Color::tellColor( ( $color || 'Black' ), $pat->{ColorSpace}->{Base} ) );
		$cs = $pat->{ColorSpace}->{Name};
		$this->{Resources}->{ColorSpace}->{ $cs } = 1;
	} else {
		$color = '';
	}
	$this->{Resources}->{Pattern}->{ $pat->{Name} } = 1;
	$this->{Stream} .= ( $ground? qq{/$cs cs $color /$pat->{Name} scn }: qq{/$cs CS $color /$pat->{Name} SCN } );
}

#==================== Stroking and filling operations ====================

# Save current graph state
sub saveGState {
	my $this = shift;
	$this->{Stream} .= 'q ';
	push( @{$this->{XML}}, qq{<Exec Cmd="SaveGState" />} ) unless( @{$this->{CallStack}} );
}

# Restore previous graph state
sub restoreGState {
	my $this = shift;
	$this->{Stream} .= 'Q ';
	push( @{$this->{XML}}, qq{<Exec Cmd="RestoreGState" />} ) unless( @{$this->{CallStack}} );
}

# Stroke
sub stroke {
	my $this = shift;
	$this->{Stream} .= 'S ';
	push( @{$this->{XML}}, qq{<Exec Cmd="Stroke" />} ) unless( @{$this->{CallStack}} );
}

# Fill
sub fill {
	my( $this, $eof ) = @_;
	$eof ||= 0;
	$this->{Stream} .= $eof? 'f* ' : 'f ';
	push( @{$this->{XML}}, qq{<Exec Cmd="Fill" Eof="$eof" />} ) unless( @{$this->{CallStack}} );
}

# Stroke and fille
sub strokeFill {
	my( $this, $eof ) = @_;
	$eof ||= 0;
	$this->{Stream} .= $eof? 'b* ' : 'b ';
	push( @{$this->{XML}}, qq{<Exec Cmd="StrokeFill" Eof="$eof" />} ) unless( @{$this->{CallStack}} );
}

# Close a SUBpath and connect to the starting point with a straight line
sub closeSubPath {
	my $this = shift;
	$this->{Stream} .= 'h ';
	push( @{$this->{XML}}, qq{<Exec Cmd="CloseSubPath" />} ) unless( @{$this->{CallStack}} );
}

# Close a path
sub closePath {
	my $this = shift;
	$this->{Stream} .= 'n ';
	push( @{$this->{XML}}, qq{<Exec Cmd="ClosePath" />} ) unless( @{$this->{CallStack}} );
}

# Open a new graphic state
sub newPath {
	my $this = shift;
	push( @{$this->{XML}}, qq{<Exec Cmd="NewPath" />} ) unless( @{$this->{CallStack}} );
	push( @{$this->{CallStack}}, 1 );
	$this->restoreGState( );
	$this->saveGState( );
	$this->closePath( );
	pop( @{$this->{CallStack}} );
}

# Set intersection of clipping paths. $eof tells if or not to invode the even-odd filling rule
sub intersect {
	my( $this, $eof ) = @_;
	$eof ||= 0;
	$this->{Stream} .= ( $eof? 'W* ': 'W ' );
	push( @{$this->{XML}}, qq{<Exec Cmd="Intersect" Eof="$eof" />} ) unless( @{$this->{CallStack}} );
}

# Connect current position to new position with a line (invisible yet). Also move to new position.
sub connectTo {
	my( $this, $x, $y ) = @_;
	push( @{$this->{XML}}, qq{<LineTo X="$x" Y="$y" PathOnly="1" />} ) unless( @{$this->{CallStack}} );
	$x = &PDF::tellSize( $x );
	$y = &PDF::tellSize( $y );
	$this->{x} = $this->{Container}->left( ) + $x;
	$this->{y} = $this->{Container}->bottom( ) + $y;
	$this->{Stream} .= sprintf( "%.4f %.4f l $GraphContent::endln", $this->{x}, $this->{y} );
}

# Draw a Bezier curve over three points, and move current position to the last point. Type can be:
#	0	Three points specified. The first two are control points.
#	1	Two points specified. The first one is the control point for the ending side.
#	2	Two points specified. The first one is the control point for the starting side.
sub curveTo {
	my( $this, $type, @coords ) = @_;
	push( @{$this->{XML}}, join( ', ', qq{<CurveTo Type="$type" Coords="}, @coords, qq{" />} ) ) unless( @{$this->{CallStack}} );
	for( @coords ){ $_ = &PDF::tellSize( $_ ); }
	$type %= 3;					# $type must be in the range 0 ~ 2
	my @opers = qw(c v y);		# Actual operators
	my @elems = ( 2, 1, 1 );	# Number of elements in the @coords array are 6, 4, 4, respectively
	for( 0..$elems[$type] ){
		$coords[ $_ * 2 ] += $this->{Container}->left( );
		$coords[ $_ * 2 + 1 ] += $this->{Container}->bottom( );
	}
	$this->{x} = $coords[ $elems[$type] * 2 ];
	$this->{y} = $coords[ $elems[$type] * 2 + 1];
	for( @coords ){ $_ = sprintf( "%.4f", $_ ) + 0; }
	$this->{Stream} .= join( ' ', @coords[ 0 .. ( ( $elems[$type] + 1 ) * 2 - 1 ) ], $opers[ $type ], $GraphContent::endln );
}

#=================== Convenient function ====================

# Gradient fill a rectangle. $sh must be a PDFShading object
sub gradFill {
	my( $this, $sh, $rect, $applyonly ) = @_;
	if( ref($sh) ne 'PDFShading' ){
		croak( "gradFill: Parameter is not a PDFShading object when calling this function" );
	}
	if( !$rect || ref( $rect ) ne 'Rect' ){
		croak( "gradFill: The second parameter must be a Rect" );
	}
	$applyonly ||= 0;
	push( @{$this->{XML}}, qq{<Fill Shading="$sh->{Name}" Rect="} . join( ', ', $rect->left( ) - 1, $rect->bottom( ) - 1, $rect->right( ) + 1, $rect->top( ) + 1 ) . qq{" ApplyOnly="$applyonly"/>} ) unless( @{$this->{CallStack}} );
	push( @{$this->{CallStack}}, 1 );
	unless( $applyonly ){
		$this->drawRectAt( $rect, 3 );
		$this->intersect( 1 );
		$this->closePath( );
		$this->moveTo( $rect->left( ) - $this->{Container}->left( ), $rect->bottom( ) - $this->{Container}->bottom( ), 1 );
	}
	$this->{Stream} .= join( ' ', 'q', $rect->width( ), 0, 0, $rect->height( ), $rect->left( ), $rect->bottom( ), 'cm', qq{/$sh->{Name} sh Q } );
	$this->{Resources}->{Shading}->{ $sh->{Name} } = 1;
	pop( @{$this->{CallStack}} );
}

# Texture fill a rectangle. $pat must be a PDFTexture object
sub textureFill( ){
	my( $this, $pat, $rect ) = @_;
	if( ref($pat) ne 'PDFTexture' ){
		croak( "textureFill: Parameter is not a PDFTexture object when calling this function" );
	}
	unless( @{$this->{CallStack}} ){
		push( @{$this->{XML}}, join( ', ', qq{<Fill Texture="$pat->{Name}" Rect="}, $rect->left( ), $rect->bottom( ), $rect->right( ), $rect->top( ), qq{" />} ) );
	}
	$this->{Stream} .= qq{/Pattern cs /$pat->{Name} scn };
	push( @{$this->{CallStack}}, 1 );
	$this->moveTo( $rect->left( ) - $this->{Container}->left( ), $rect->bottom( ) - $this->{Container}->bottom( ), 1 );
	$this->drawRect( $rect->width( ), $rect->height( ), 1 );
	$this->{Resources}->{Pattern}->{ $pat->{Name} } = 1;
	pop( @{$this->{CallStack}} );
}

# Draw a line to, and move to, a new position
# The parameters could be either:
#	x, y, line width, color, pathonly ( 1 or 0 )
# or preferrably (any of the hash keys can be omitted):
#	x, y, {'Arrow'=>[ length, breadth, tilt ], 'Width'=>width, 'Color'=>'Color'}
# Note the arrowhead is filled rather than stroked.
sub lineTo {
	my( $this, $x, $y, $lw, $cl, $pathonly ) = @_;
	push( @{$this->{CallStack}}, 1 );
	my @xmls = ( qq{X="$x"}, qq{Y="$y"} );
	$x = &PDF::tellSize( $x );
	$y = &PDF::tellSize( $y );
	my @points = ( );	# Used to show arrow head
	if( ref( $lw ) eq 'HASH' ){
		if( $lw->{Arrow} ){
			push( @xmls, qq{Arrow="$lw->{Arrow}->[0], $lw->{Arrow}->[1], $lw->{Arrow}->[2]"} );
			my $theta = atan2( $y - $this->{y} + $this->{Container}->bottom( ), $x - $this->{x} + $this->{Container}->left( ) );
			my( $tmpx, $tmpy ) = ( $x - $lw->{Arrow}->[0] * cos( $theta ), $y - $lw->{Arrow}->[0] * sin( $theta ) );
			my $alpha = $lw->{Arrow}->[2] / 180 * 3.1416;
			my $breadth = $lw->{Arrow}->[1];
			push( @points,
				$x, $y,
				$tmpx - $breadth * sin( $theta ), $tmpy + $breadth * cos( $theta ),
				$tmpx - $breadth * sin( $theta ) + $breadth / cos( $alpha ) * sin( $alpha + $theta ),
				$tmpy + $breadth * cos( $theta ) - $breadth / cos( $alpha ) * cos( $alpha + $theta ),
				$tmpx + $breadth * sin( $theta ), $tmpy - $breadth * cos( $theta ),
			);
		}
		$cl = $lw->{Color};
		$pathonly = $lw->{PathOnly};
		$lw = $lw->{Width};
		( $x, $y ) = @points[ (4, 5) ];	# Retract the ending point to avoid a butt shown in front of the arrow
	}
	if( $lw ){
		push( @xmls, qq{Width="$lw"} );
		$this->setLineWidth( &PDF::tellSize( $lw ) );
	}
	if( $cl ){
		push( @xmls, qq{Color="$cl"} );
		$this->setColor( $cl );
	}
	if( $pathonly ){
		push( @xmls, qq{PathOnly="1"} );
		$this->setColor( $cl );
	}
	$this->{x} = $this->{Container}->left( ) + $x;
	$this->{y} = $this->{Container}->bottom( ) + $y;
	my $stroke = ( $pathonly? '': 'S' );
	$this->{Stream} .= "$this->{x} $this->{y} l $stroke $GraphContent::endln";
	if( @points ){
		$this->drawPolyLine( ( $pathonly? 3: 1 ), @points );
	}
	pop( @{$this->{CallStack}} );
	unless( @{$this->{CallStack}} ){
		push( @{$this->{XML}}, join( ' ', '<LineTo', @xmls, ' />' ) );
	}
}

# Draw a polyline defined by a series of points
sub drawPolyLine {
	my( $this, $fill, @coords ) = @_;
	push( @{$this->{XML}}, qq{<PolyLine Fill="$fill" Coords="} . join( ', ', @coords ) . qq{"/>} ) unless( @{$this->{CallStack}} );
	push( @{$this->{CallStack}}, 1 );
	for( @coords ){ $_ = &PDF::tellSize( $_ ); }
	my @start = splice( @coords, 0, 2 );
	$this->moveTo( @start );
	while( scalar @coords > 1 ){
		$this->connectTo( splice( @coords, 0, 2 ) );
	}
	$fill %= 4;
	$this->{Stream} .= [ 'S', 'f', 'B', 'h' ]->[ $fill ];
	$this->{Stream} .= $GraphContent::endln;
	pop( @{$this->{CallStack}} );
}

# Draw a rectanlge. Do NOT move current position.
sub drawRect {
	my( $this, $w, $h, $fill, $centered ) = @_;
	unless( @{$this->{CallStack}} ){
		my @xml = ( qq{Width="$w" Height="$h"} );
		defined $centered && push( @xml, qq{Centered="$centered"} );
		defined $fill && push( @xml, qq{Fill="$fill"} );
		push( @{$this->{XML}}, join( ' ', '<DrawRect', @xml, '/>' ) );
	}
	push( @{$this->{CallStack}}, 1 );
	$w = sprintf( "%.4f", &PDF::tellSize( $w ) );
	$h = sprintf( "%.4f", &PDF::tellSize( $h ) );
	$fill ||= 0;	$fill %= 4;
	# $fill = 0 to stroke, 1 to fill, 2 to stroke and fill, 3 to close path only, and 4 to close path and apply even-odd rule
	# If $centered is set, then draw the rectangle around the point
	my $gs = [ 'S', 'f', 'B', 'h' ]->[ $fill ];
	if( $centered ){
		$this->{Stream} .= join( ' ',
			$this->{x} - $w/2, $this->{y} - $h/2,
			$w, $h, 're',
			$this->{x}, $this->{y}, 'm',
			$GraphContent::endln, $gs, $GraphContent::endln );
	} else {
		$this->{Stream} .= "$this->{x} $this->{y} $w $h re $gs $GraphContent::endln";
	}
	pop( @{$this->{CallStack}} );
	if( $centered ){
		return new Rect( $this->{x} - $w / 2, $this->{y} - $h / 2, $this->{x} + $w / 2, $this->{y} + $h / 2 );
	} else {
		return new Rect( $this->{x}, $this->{y}, $this->{x} + $w - 1, $this->{y} + $h - 1 );
	}
}

# For use with a Rect object which has ABSOLUTE coordinates
sub drawRectAt {
	my( $this, $rect, $fill ) = @_;
	$this->moveTo( $rect->left( ) - $this->{Container}->left( ), $rect->bottom( ) - $this->{Container}->bottom( ) );
	$this->drawRect( $rect->width( ), $rect->height( ), $fill );
}

# Draw a rectangle to a given position in RELATIVE coordinates
sub drawRectTo {
	my( $this, $x, $y, $fill ) = @_;
	$x = &PDF::tellSize( $x );
	$y = &PDF::tellSize( $y );
	my $absx = $this->{Container}->left( ) + $x;
	my $absy = $this->{Container}->bottom( ) + $y;
	my( $w, $h ) = ( $absx - $this->{x}, $absy - $this->{y} );
	# Save current position. If $w or $h is negative, then must move to the bottom-left corner of the rectangle before drawing.
	my @adjpos = $this->getPos( );
	my @currpos = @adjpos;
	if( $w < 0 ){
		$w *= (-1); $adjpos[0] -= $w;
	}
	if( $h < 0 ){
		$h *= (-1); $adjpos[1] -= $h;
	}
	$this->moveTo( @adjpos );
	$this->drawRect( $w, $h, $fill );
	$this->moveTo( @currpos );
}

# Draw a rectanlge with rounded corner. Do NOT move current position.
sub drawRoundedRect {
	my( $this, $w, $h, $r, $fill, $centered, $reverse ) = @_;
	unless( @{$this->{CallStack}} ){
		my @xml = ( qq{Width="$w" Height="$h" Round="$r"} );
		defined $centered && push( @xml, qq{Centered="$centered"} );
		defined $fill && push( @xml, qq{Fill="$fill"} );
		defined $reverse && push( @xml, qq{Reverse="$reverse"} );
		push( @{$this->{XML}}, join( ' ', '<DrawRect', @xml, '/>' ) );
	}
	push( @{$this->{CallStack}}, 1 );
	$w = &PDF::tellSize( $w );
	$h = &PDF::tellSize( $h );
	$r = &PDF::tellSize( $r );
	$fill ||= 0;
	# $fill = 0 to stroke, 1 to fill, 2 to stroke and fill, 3 to close path only, and 4 to close path and apply even-odd rule
	# If $centered is set, then draw the rectangle around the point
	if( $r > &PDF::min( $w, $h ) / 2 ){
		$r = &PDF::min( $w, $h ) / 2;
	}
	my @xs = ( $r, $w - $r, $w, $w, $w - $r, $r, 0, 0 );
	my @ys = ( 0, 0, $r, $h - $r, $h, $h, $h - $r, $r );
	if( $centered ){
		for( @xs ){ $_ -= $w / 2; }
		for( @ys ){ $_ -= $h / 2; }
	}
	for( @xs ){ $_ += $this->{x} - $this->{Container}->left( ); }
	for( @ys ){ $_ += $this->{y} - $this->{Container}->bottom( ); }
	my $s = sprintf( "%.4f", $r * ( sqrt( 2 ) - 1 ) * 4 / 3 );
	if( $reverse ){
		$this->moveTo( $xs[1], $ys[1] );
		$this->connectTo( $xs[0], $ys[0] );
		$this->curveTo( 0, $xs[0] - $s, $ys[0], $xs[7], $ys[7] - $s, $xs[7], $ys[7] );
		$this->connectTo( $xs[6], $ys[6] );
		$this->curveTo( 0, $xs[6], $ys[6] + $s, $xs[5] - $s, $ys[5], $xs[5], $ys[5] );
		$this->connectTo( $xs[4], $ys[4] );
		$this->curveTo( 0, $xs[4] + $s, $ys[4], $xs[3], $ys[3] + $s, $xs[3], $ys[3] );
		$this->connectTo( $xs[2], $ys[2] );
		$this->curveTo( 0, $xs[2], $ys[2] - $s, $xs[1] + $s, $ys[1], $xs[1], $ys[1] );
		$this->connectTo( $xs[1], $ys[1] );
	} else {
		$this->moveTo( $xs[0], $ys[0] );
		$this->connectTo( $xs[1], $ys[1] );
		$this->curveTo( 0, $xs[1] + $s, $ys[1], $xs[2], $ys[2] - $s, $xs[2], $ys[2] );
		$this->connectTo( $xs[3], $ys[3] );
		$this->curveTo( 0, $xs[3], $ys[3] + $s, $xs[4] + $s, $ys[4], $xs[4], $ys[4] );
		$this->connectTo( $xs[5], $ys[5] );
		$this->curveTo( 0, $xs[5] - $s, $ys[5], $xs[6], $ys[6] + $s, $xs[6], $ys[6] );
		$this->connectTo( $xs[7], $ys[7] );
		$this->curveTo( 0, $xs[7], $ys[7] - $s, $xs[0] - $s, $ys[0], $xs[0], $ys[0] );
		$this->connectTo( $xs[0], $ys[0] );
	}
	$fill %= 4;
	my $gs = [ 'S', 'f', 'B', 'h' ]->[ $fill ];
	$this->{Stream} .= "$gs $GraphContent::endln";
	pop( @{$this->{CallStack}} );
	return new Rect( $this->{x}, $this->{y}, $this->{x} + $w - 1, $this->{y} + $h - 1 );
}

# For use with a Rect object which has ABSOLUTE coordinates
sub drawRoundedRectAt {
	my( $this, $rect, $r, $fill, $reverse ) = @_;
	$this->moveTo( $rect->left( ) - $this->{Container}->left( ), $rect->bottom( ) - $this->{Container}->bottom( ) );
	$this->drawRoundedRect( $rect->width( ), $rect->height( ), $r, $fill, $reverse );
	return $r;
}

# Draw a rectangle to a given position in RELATIVE coordinates
sub drawRoundedRectTo {
	my( $this, $x, $y, $r, $fill ) = @_;
	$x = &PDF::tellSize( $x );
	$y = &PDF::tellSize( $y );
	my $absx = $this->{Container}->left( ) + $x;
	my $absy = $this->{Container}->bottom( ) + $y;
	my( $w, $h ) = ( $absx - $this->{x}, $absy - $this->{y} );
	my @adjpos = $this->getPos( );
	my @currpos = @adjpos;
	if( $w < 0 ){
		$w *= (-1); $adjpos[0] -= $w;
	}
	if( $h < 0 ){
		$h *= (-1); $adjpos[1] -= $h;
	}
	$this->moveTo( @adjpos );
	$this->drawRoundedRect( $w, $h, $r, $fill, $reverse );
	$this->moveTo( @currpos );
	return new Rect( $this->{x}, $this->{y}, $absx, $absy );
}

# Draw a circular arc. Need radius, from what degree, to what degree, and fill mode
sub drawArc {
	my( $this, $r, $from, $to, $fill ) = @_;
	if( $from < 0 ){ $from *= -1; }
	if( $to < 0 ){ $to *= -1; }
	unless( @{$this->{CallStack}} ){
		my @xml = ( qq{Radius="$r" From="$from" To="$to"} );
		defined $fill && push( @xml, qq{Fill="$fill"} );
		push( @{$this->{XML}}, join( ' ', '<DrawArc', @xml, '/>' ) );
	}
	push( @{$this->{CallStack}}, 1 );
	$r = &PDF::tellSize( $r );
	my $sqr = 4 * ( sqrt( 2 ) - 1 );
	my $s = $sqr * $r / 3;
	my @angles = ( $from, $to );
	if( $from > $to ){
		@angles = reverse @angles;
	}
	my @xmods = (
		[ 0, $s, $r, $r ],
		[ -1 * $r, -1 * $r, -1 * $s, 0 ],
		[ 0, -1 * $s, -1 * $r, -1 * $r ],
		[ $r, $r, $s, 0 ]
	);
	my @ymods = (
		[ $r, $r, $s, 0 ],
		[ 0, $s, $r, $r ],
		[ -1 * $r, -1 * $r, -1 * $s, 0 ],
		[ 0, -1 * $s, -1 * $r, -1 * $r ]
	);
	$fill %= 4;
	my $gs = [ 'S', 'f', 'B', 'h' ]->[ $fill ];
	my( $x, $y ) = ( $this->{x}, $this->{y} );
	my @phases = ( );
	# Sequence of points in @xpos and @ypos:
	# 000, 001, 011, 111; 00t, 01t, 11t, 0tt, 1tt, ttt (cf. de Casteljau algorithm)
	# The control points for segment 0..t are 000, 00t, 0tt, ttt (0479); those for segment t..1 are ttt, 1tt, 11t, 111 (9863).
	my @xpos = ( [], [] );
	my @ypos = ( [], [] );
	for my $i ( 0..1 ){
		my $phase = int( $angles[$i] / 90 );
		if( $phase > 3 ){ $phase = 3; }
		push( @phases, $phase );
		$angles[$i] *= 3.1416 / 180;
		# If ending point is in the same phase as the starting point, then use the first 0..t segment as the initial curve;
		# Otherwise, that portion of curve is independent on the first portion.
		if( $i && $phase == $phases[0] ){
			push( @{$xpos[1]}, $xpos[0]->[0], $xpos[0]->[4], $xpos[0]->[7], $xpos[0]->[9] );
			push( @{$ypos[1]}, $ypos[0]->[0], $ypos[0]->[4], $ypos[0]->[7], $ypos[0]->[9] );
		} else {
			map{ push( @{$xpos[$i]}, $x + $_ ); } @{$xmods[$phase]};
			map{ push( @{$ypos[$i]}, $y + $_ ); } @{$ymods[$phase]};
		}
		my $t = 0.5;
		if( cos( $angles[$i] ) == 0 ){
			$t = $i;
		} else {
			my $tan = sin( $angles[$i] ) / cos( $angles[$i] );
			my $cx = 3 * ( $xpos[$i]->[1] - $xpos[$i]->[0] );
			my $bx = 3 * ( $xpos[$i]->[2] - $xpos[$i]->[1] ) - $cx;
			my $ax = $xpos[$i]->[3] - $xpos[$i]->[0] - $bx - $cx;
			my $cy = 3 * ( $ypos[$i]->[1] - $ypos[$i]->[0] );
			my $by = 3 * ( $ypos[$i]->[2] - $ypos[$i]->[1] ) - $cy;
			my $ay = $ypos[$i]->[3] - $ypos[$i]->[0] - $by - $cy;
			my $a = $ay - $tan * $ax;
			my $b = $by - $tan * $bx;
			my $c = $cy - $tan * $cx;
			my $d = ( $ypos[$i]->[0] - $y ) - $tan * ( $xpos[$i]->[0] - $x );
			my $tsave;
			# Now uses Newton's secondary derivative method to find the true t value.
			do {
				$tsave = $t;
				my $f0 = $a * $t ** 3 + $b * $t ** 2 + $c * $t + $d;
				my $f1 = 3 * $a * $t ** 2 + 2 * $b * $t + $c;
				my $f2 = 6 * $a * $t + 2 * $b;
				$t -= $f0 / ( $f1 - $f2 * $f0 / 2 / $f1 );
			} while( abs( $t - $tsave ) > 1e-6 );
		}
		$s = 1 - $t;
		foreach my $j ( 0, 1, 2, 4, 5, 7 ){
			push( @{$xpos[$i]}, $s * $xpos[$i]->[$j] + $t * $xpos[$i]->[$j+1] );
			push( @{$ypos[$i]}, $s * $ypos[$i]->[$j] + $t * $ypos[$i]->[$j+1] );
		}
	}
	my $op = ( $fill == 3? 'm': 'l' );	# Fixed 01/06/2003 Should not introduce a straight line
	if( $fill ){
		$this->{Stream} .= qq{$x $y m $xpos[1]->[9] $ypos[1]->[9] $op $GraphContent::endln};
	} else {
		$this->{Stream} .= qq{$xpos[1]->[9] $ypos[1]->[9] m $GraphContent::endln};
	}
	$this->{Stream} .= sprintf( "%.4f %.4f %.4f %.4f %.4f %.4f c $GraphContent::endln", $xpos[1]->[8], $ypos[1]->[8], $xpos[1]->[6], $ypos[1]->[6], $xpos[1]->[3], $ypos[1]->[3] );
	if( $phases[1] - $phases[0] > 1 ){
		for( reverse $phases[0]+1 .. $phases[1]-1 ){
			my $px = $xmods[$_];
			my $py = $ymods[$_];
			$this->{Stream} .= sprintf( "%.4f %.4f %.4f %.4f %.4f %.4f c $GraphContent::endln", $px->[1]+$x, $py->[1]+$y, $px->[2]+$x, $py->[2]+$y, $px->[3]+$x, $py->[3]+$y );
		}
	}
	if( $phases[1] != $phases[0] ){
		$this->{Stream} .= sprintf( "%.4f %.4f %.4f %.4f %.4f %.4f c $GraphContent::endln", $xpos[0]->[4], $ypos[0]->[4], $xpos[0]->[7], $ypos[0]->[7], $xpos[0]->[9], $ypos[0]->[9] );
	}
	if( $fill ){
		$this->{Stream} .= sprintf( "%.4f %.4f $op $gs $GraphContent::endln", $x, $y );
	} else {
		$this->{Stream} .= sprintf( "$gs %.4f %.4f m $GraphContent::endln", $x, $y );
	}
	pop( @{$this->{CallStack}} );
	return new Rect( $this->{x} - $r, $this->{y} - $r, $this->{x} + $r, $this->{y} + $r );
}

# Draw a circular arc. Need radius, from what degree, to what degree, and fill mode
sub drawOvalArc {
	my( $this, $a, $b, $from, $to, $fill ) = @_;
	unless( @{$this->{CallStack}} ){
		my @xml = ( qq{A="$a" B="$b" From="$from" To="$to"} );
		defined $fill && push( @xml, qq{Fill="$fill"} );
		push( @{$this->{XML}}, join( ' ', '<DrawArc', @xml, '/>' ) );
	}
	push( @{$this->{CallStack}}, 1 );
	$a = &PDF::tellSize( $a );
	$b = &PDF::tellSize( $b );
	$from ||= 0;	$to ||= 180;	$fill ||= 0;
	if( $b > $a ){
		$this->moveBy( ( $this->{x} - $this->{Container}->left( ) ) * ( $b / $a - 1 ), 0 );
		$this->{Stream} .= sprintf( "q %.4f 0 0 1 0 0 cm$GraphContent::endln", $a / $b );
		$this->drawArc( $b, $from, $to, $fill );
	} else {
		$this->moveBy( 0, ( $this->{y} - $this->{Container}->bottom( ) ) * ( $a / $b - 1 ) );
		$this->{Stream} .= sprintf( "q 1 0 0 %.4f 0 0 cm$GraphContent::endln", $b / $a );
		$this->drawArc( $a, $from, $to, $fill );
	}
	$this->{Stream} .= "Q ";
	pop( @{$this->{CallStack}} );
}

# Draw a circle
sub drawCircle {
	my( $this, $r, $fill, $reverse ) = @_;
	unless( @{$this->{CallStack}} ){
		my @xml = ( qq{Radius="$r"} );
		defined $reverse && push( @xml, qq{Reverse="$reverse"} );
		defined $fill && push( @xml, qq{Fill="$fill"} );
		push( @{$this->{XML}}, join( ' ', '<DrawCircle', @xml, '/>' ) );
	}
	$r = &PDF::tellSize( $r );
	$fill ||= 0;	$reverse ||= 0;
	my $s = sprintf( "%.4f", $r * ( sqrt( 2 ) - 1 ) * 4 / 3 );
	my $gs = [ 'S', 'f', 'B', 'h' ]->[ $fill ];
	my( $x, $y ) = ( $this->{x}, $this->{y} );
	if( $reverse ){
		$this->{Stream} .= join( ' ',
			$x, $y - $r, 'm',
			$x - $s, $y - $r, $x - $r, $y - $s, $x - $r, $y, 'c',
			$x - $r, $y + $s, $x - $s, $y + $r, $x, $y + $r, 'c',
			$x + $s, $y + $r, $x + $r, $y + $s, $x + $r, $y, 'c',
			$x + $r, $y - $s, $x + $s, $y - $r, $x, $y - $r, 'c',
			$x, $y, 'm',
			$GraphContent::endln, $gs, $GraphContent::endln );
	} else {
		$this->{Stream} .= join( ' ',
			$x, $y - $r, 'm',
			$x + $s, $y - $r, $x + $r, $y - $s,	$x + $r, $y, 'c',
			$x + $r, $y + $s, $x + $s, $y + $r, $x, $y + $r, 'c',
			$x - $s, $y + $r, $x - $r, $y + $s, $x - $r, $y, 'c',
			$x - $r, $y - $s, $x - $s, $y - $r, $x, $y - $r, 'c',
			$x, $y, 'm',
			$GraphContent::endln, $gs, $GraphContent::endln );
	}
	return new Rect( $this->{x} - $r, $this->{y} - $r, $this->{x} + $r, $this->{y} + $r );
}

# Draw an ellipse
sub drawEllipse {
	my( $this, $a, $b, $theta, $fill ) = @_;
	unless( @{$this->{CallStack}} ){
		my @xml = ( qq{A="$a"}, qq{B="$b"} );
		defined $fill && push( @xml, qq{Fill="$fill"} );
		defined $theta && push( @xml, qq{Rotation="$theta"} );
		push( @{$this->{XML}}, join( ' ', '<DrawEllipse', @xml, '/>' ) );
	}
	$theta ||= 0;
	$fill ||= 0;
	$a = &PDF::tellSize( $a );
	$b = &PDF::tellSize( $b );
	$theta *= 3.1416 / 180;
	my $alpha = 3.1416 / 8;
	my $s = 4 * ( 1 - cos( $alpha ) ) / ( 3 * sin( $alpha ) );
	my( @xoff, @yoff, @xpos, @ypos ) = ( );
	for( 0..23 ){
		my $cs = cos( $_ * 2 * $alpha );
		my $sn = sin( $_ * 2 * $alpha );
		my $k = $_ * 3;
		my $j = ( $k? $k - 1: 23 );
		$xoff[$k] = $a * $cs;
		$yoff[$k] = $b * $sn;
		$xoff[$j] = $xoff[$k] + $s * $a * $sn;
		$yoff[$j] = $yoff[$k] - $s * $b * $cs;
		$xoff[$k+1] = $xoff[$k] - $s * $a * $sn;
		$yoff[$k+1] = $yoff[$k] + $s * $b * $cs;
	}
	$xoff[24] = $xoff[0];
	$yoff[24] = $yoff[0];
	if( $theta ){
		for( 0..24 ){
			$xpos[$_] = $xoff[$_] * cos( $theta ) - $yoff[$_] * sin( $theta ) + $this->{x};
			$ypos[$_] = $xoff[$_] * sin( $theta ) + $yoff[$_] * cos( $theta ) + $this->{y};
		}
	} else {
		@xpos = map{ $_ + $this->{x} } @xoff;
		@ypos = map{ $_ + $this->{y} } @yoff;
	}
	foreach( @xpos, @ypos ){
		$_ = sprintf( "%.4f", $_ );
	}
	$this->{Stream} .= qq{$xpos[0] $ypos[0] m $GraphContent::endln};
	for( 0..7 ){
		$this->{Stream} .= join( ' ',
			$xpos[3*$_+1], $ypos[3*$_+1],
			$xpos[3*$_+2], $ypos[3*$_+2],
			$xpos[3*$_+3], $ypos[3*$_+3], 'c', $GraphContent::endln );
	}
	my $gs = [ 'S', 'f', 'B', 'h' ]->[ $fill ];
	$this->{Stream} .= qq{$gs $this->{x} $this->{y} m $GraphContent::endln};
	my $r = &PDF::max( $a, $b );
	return new Rect( $this->{x} - $r, $this->{y} - $r, $this->{x} + $r, $this->{y} + $r );
}

# Same as drawing an ellipse
sub drawOval {
	my( $this, $a, $b, $theta, $fill ) = @_;
	return $this->drawEllipse( $a, $b, $theta, $fill );
}

# Draw an polygon (regular shape). Need radius, number of sides, rotation angle from vertical directation, tilt angle of sides, and fill mode
sub drawPolygon {
	my( $this, $r, $n, $theta, $beta, $fill, $reverse ) = @_;
	unless( @{$this->{CallStack}} ){
		my @xml = ( qq{Radius="$r" Sides="$n"} );
		defined $theta && push( @xml, qq{Rotation="$theta"} );
		defined $beta && push( @xml, qq{Tilt="$beta"} );
		defined $fill && push( @xml, qq{Fill="$fill"} );
		defined $reverse && push( @xml, qq{Reverse="$reverse"} );
		push( @{$this->{XML}}, join( ' ', '<DrawPolygon', @xml, '/>' ) );
	}
	$r = &PDF::tellSize( $r );
	$theta *= 3.1416 / 180;
	unless( $n % 2 ){
		$theta += 3.1416 / 2;
	}
	$beta *= 3.1416 / 180;
	my @Points = ( );
	my $sa = 3.1416 / $n;
	my $r2 = $r / cos( $sa ) / ( ( sin( $sa ) / cos( $sa ) ) * ( sin( $beta ) / cos( $beta ) ) + 1 );
	for my $i ( 0 .. (2 * $n) ){
		my $ang = $i * $sa + $theta;
		if( $i % 2 ){
			push( @Points, [ $this->{x} + $r * sin( $ang ), $this->{y} - $r * cos( $ang ) ] );
		} else {
			push( @Points, [ $this->{x} + $r2 * sin( $ang ), $this->{y} - $r2 * cos( $ang ) ] );
		}
	}
	if( $reverse ){ @Points = reverse @Points; }
	$this->{Stream} .= sprintf( " %.4f %.4f m $GraphContent::endln", $Points[0]->[0], $Points[0]->[1] );
	for( 1..$#Points ){
		$this->{Stream} .= sprintf( " %.4f %.4f l $GraphContent::endln", $Points[$_]->[0], $Points[$_]->[1] );
	}
	$fill ||= 0;
	$fill %= 4;
	my $gs = [ 's', 'f', 'B', 'h' ]->[ $fill ];
	$this->{Stream} .= $gs . $GraphContent::endln;
	return new Rect( $this->{x} - $r, $this->{y} - $r, $this->{x} + $r, $this->{y} + $r );
}

# Draw a grid, needs total width, total height, fill mode and a hash ref for attributes
sub drawGrid {
	my( $this, $w, $h, $fill, $attr ) = @_;
	unless( @{$this->{CallStack}} || $attr->{NoDraw} ){
		my @xmls = ( );
		for( qw(XSpacing YSpacing BorderWidth XGrids YGrids NoFrame) ){
			if( defined $attr->{$_} ){
				push( @xmls, qq{$_="$attr->{$_}"} );
			} else {
				$attr->{$_} = 0;
			}
		}
		for( qw(Widths Heights) ){
			next unless( defined $attr->{$_} );
			if( ref( $attr->{$_} ) ne 'ARRAY' ){
				croak( "drawGrid/Table: Widths and Heights attributes must be array references." );
			}
			push( @xmls, qq{$_="} . join( ', ', @{$attr->{$_}} ) . '"' );
		}
		push( @{$this->{XML}}, qq{<Table Width="$w" Height="$h" Fill="$fill" } . join( ' ', @xmls ) . ' />' );
	}
	for( $w, $h, $attr->{XSpacing}, $attr->{YSpacing}, $attr->{BorderWidth} ){
		$_ = &PDF::tellSize( $_ );
	}
	my( @xs, @ys );
	my( $i, $j );
	my $x = $this->{x} || 0;
	my $y = $this->{y} || 0;
	unless( ( $attr->{XGrids} || $attr->{XSpacing} || $attr->{Widths} ) && ( $attr->{YGrids} || $attr->{YSpacing} || $attr->{Heights} ) ){
		croak( "drawGrid/Table: Please specify either a grid number, a spacing, or a width array for both axes." );
	}
	if( $attr->{Widths} ){
		$w -= $attr->{BorderWidth} * scalar @{$attr->{Widths}};
		my( $v, $d, $ptotal, $ecount ) = ( 0, $w, 0, 0 );
		for( @{$attr->{Widths}} ){
			if( /^(\d+)\s*\#/ ){
				$ptotal += $1;
			} elsif( /^\s*\*/ ){
				$ecount++;
			} elsif( /^\s*(\d+)%/ ){
				$_ = $1 * $w / 100;
			} else {
				$_ = &PDF::tellSize( $_ );
				$d -= $_;
			}
		}
		for( @{$attr->{Widths}} ){
			if( /^(\d+)\s*\#/ ){
				$_ = $1 * $d / $ptotal;
			} elsif( /^\s*\*/ ){
				$_ = $d / $ecount;
			}
			push( @xs, $v - $attr->{BorderWidth} / 2, $v + $attr->{BorderWidth} / 2 );
			$v += $_;
		}
		push( @xs, $w - $attr->{BorderWidth} / 2, $w + $attr->{BorderWidth} / 2 );
	} elsif( $attr->{XGrids} ){
		for( $i = 0; $i <= $attr->{XGrids}; $i++ ){
			push( @xs, $w / $attr->{XGrids} * $i - $attr->{BorderWidth} / 2, $w / $attr->{XGrids} * $i + $attr->{BorderWidth} / 2 );
		}
	} else {
		my $v = 0;
		while( $v <= $w ){
			push( @xs, $v - $attr->{BorderWidth} / 2, $v + $attr->{BorderWidth} / 2 );
			$v += $attr->{XSpacing};
		}
		if( $v > $w && ( $v - $w ) > $attr->{BorderWidth} && ( $v - $w ) < $attr->{XSpacing} ){
			if( $attr->{NoPartial} ){
				pop( @xs );
				push( @xs, $w + $attr->{BorderWidth} / 2 );
			} else {
				push( @xs, $w - $attr->{BorderWidth} / 2, $w + $attr->{BorderWidth} / 2 );
			}
		}
	}
	if( $attr->{Heights} ){
		$h -= $attr->{BorderWidth} * scalar @{$attr->{Heights}};
		my( $v, $d, $ptotal, $ecount ) = ( $h, $h, 0, 0 );
		for( @{$attr->{Heights}} ){
			if( /^(\d+)\s*\#/ ){
				$ptotal += $1;
			} elsif( /^\s*\*/ ){
				$ecount++;
			} elsif( /^\s*(\d+)%/ ){
				$_ = $1 * $h / 100;
			} else {
				$_ = &PDF::tellSize( $_ );
				$d -= $_;
			}
		}
		for( @{$attr->{Heights}} ){
			if( /^(\d+)\s*\#/ ){
				$_ = $1 * $d / $ptotal;
			} elsif( /^\s*\*/ ){
				$_ = $d / $ecount;
			}
			push( @ys, $v + $attr->{BorderWidth} / 2, $v - $attr->{BorderWidth} / 2 );
			$v -= $_;
		}
		push( @ys, $attr->{BorderWidth} / 2, 0 - $attr->{BorderWidth} / 2 );
	} elsif( $attr->{YGrids} ){
		for( $i = $attr->{YGrids}; $i >= 0; $i-- ){
			push( @ys, $h / $attr->{YGrids} * $i + $attr->{BorderWidth} / 2, $h / $attr->{YGrids} * $i - $attr->{BorderWidth} / 2 );
		}
	} else {
		my $v = $h;
		while( $v >= 0 ){
			push( @ys, $v + $attr->{BorderWidth} / 2, $v - $attr->{BorderWidth} / 2 );
			$v -= $attr->{YSpacing};
		}
		if( $v < 0 && (-1) * $v > $attr->{BorderWidth} && (-1) * $v < $attr->{YSpacing} ){
			if( $attr->{NoPartial} ){
				pop( @ys );
				push( @ys, $attr->{BorderWidth} / (-2) );
			} else {
				push( @ys, $attr->{BorderWidth} / 2, $attr->{BorderWidth} / (-2) );
			}
		}
	}
	for( @xs ){ $_ = sprintf( "%.4f", $_ + $x ); }
	for( @ys ){ $_ = sprintf( "%.4f", $_ + $y ); }
	if( $attr->{NoFrame} || !$attr->{BorderWidth} || $attr->{NoDraw} ){
		pop( @xs ); shift( @xs ); pop( @ys ); shift( @ys );
	} else {
		$this->{Stream} .= join( ' ', $xs[0], $ys[-1], pop( @xs ) - shift( @xs ), shift( @ys ) - pop( @ys ), 're', 'S', $GraphContent::endln );
	}
	$fill ||= 0;
	$fill %= 4;
	my $gs = [ 'S', 'f', 'B', 'h' ]->[ $fill ];
	if( $fill == 3 ){	# Clip path
		$this->{Stream} .= qq{W $GraphContent::endln} unless( $attr->{NoDraw} );
	}
	if( !$attr->{BorderWidth} && !$attr->{NoDraw} ){
		my $i = 0;
		if( $fill ){
			$this->{Stream} .= join( ' ', $xs[0], $ys[-1], $xs[-1] - $xs[0], $ys[0] - $ys[-1], 're', ( $fill == 3? 'h': 'f' ), $GraphContent::endln );
		}
		if( $fill == 2 || $fill == 0 ){
			while( $i < scalar @xs ){
				$this->{Stream} .= join( ' ', $xs[$i], $ys[0], 'm', $xs[$i], $ys[-1], 'l', $GraphContent::endln );
				$i += 2;
			}
			$i = 0;
			while( $i < scalar @ys ){
				$this->{Stream} .= join( ' ', $xs[0], $ys[$i], 'm', $xs[-1], $ys[$i], 'l', $GraphContent::endln );
				$i += 2;
			}
			$this->{Stream} .= join( ' ', $xs[0], $ys[-1], 'm', $xs[-1], $ys[-1], 'l', $xs[-1], $ys[0], 'l', 'S', $GraphContent::endln );
		}
	} else {
		for( my $i = 0; $i < $#xs; $i += 2 ){
			for( my $j = $#ys; $j > 0; $j -= 2 ){
				unless( $attr->{NoDraw} ){
					$this->{Stream} .= join( ' ', $xs[$i], $ys[$j], $xs[$i+1] - $xs[$i], $ys[$j-1] - $ys[$j], 're', $gs, $GraphContent::endln );
				}
			}
		}
	}
	my @rects = ( );
	for( my $i = 0; $i < $#xs; $i += 2 ){
		for( my $j = 1; $j <= $#ys; $j += 2 ){
			$rects[ ( $j - 1 ) / 2 * ( scalar @xs / 2 ) + $i / 2 ] = new Rect( $xs[$i], $ys[$j], $xs[$i+1], $ys[$j-1] );
		}
	}
	$PDF::root->setCurrTable( new TableGrid( scalar @xs / 2, scalar @ys / 2, \@rects ) );
	return @rects;
}

sub drawGridAt {
	my( $this, $rect, $fill, $attr ) = @_;
	$this->moveTo( $rect->left( ) - $this->{Container}->left( ), $rect->bottom( ) - $this->{Container}->bottom( ) );
	return $this->drawGrid( $rect->width( ), $rect->height( ), $fill, $attr );
}

# Draw a grid to a position
sub drawGridTo {
	my( $this, $x, $y, $fill, $attr ) = @_;
	$x = &PDF::tellSize( $x );
	$y = &PDF::tellSize( $y );
	if( $x < 0 ){
		$x = &PDF::max( 0, $this->{Container}->right( ) + $x - $this->{Container}->left( ) );
	}
	if( $y < 0 ){
		$y = &PDF::max( 0, $this->{Container}->top( ) + $y - $this->{Container}->bottom( ) );
	}
	# The following a few lines are copied from drawRectTo.
	my $absx = $this->{Container}->left( ) + $x;
	my $absy = $this->{Container}->bottom( ) + $y;
	my( $w, $h ) = ( $absx - $this->{x}, $absy - $this->{y} );
	my @adjpos = $this->getPos( );
	my @currpos = @adjpos;
	if( $w < 0 ){
		$w *= (-1); $adjpos[0] -= $w;
	}
	if( $h < 0 ){
		$h *= (-1); $adjpos[1] -= $h;
	}
	$this->moveTo( @adjpos );
	my @rects = $this->drawGrid( $w, $h, $fill, $attr );
	$this->moveTo( @currpos );
	return @rects;
}

# Requires two arrays each having 6 elements, returns one such array.
sub transform {
	my $this = shift;
	my @m = @_;
	return ( 
		$m[0] * $m[6] + $m[1] * $m[8],
		$m[0] * $m[7] + $m[1] * $m[9],
		$m[2] * $m[6] + $m[3] * $m[8],
		$m[2] * $m[7] + $m[3] * $m[9],
		$m[4] * $m[6] + $m[5] * $m[8] + $m[10],
		$m[4] * $m[7] + $m[5] * $m[9] + $m[11],
	);
}

# Show an image. $oImage must be an ImageContent object.

sub showImage {
	my( $this, $oImage, $left, $bottom, $attr ) = @_;
	if( ref( $bottom ) eq 'ImageContent' ){
		( $left, $bottom, $oImage ) = ( $oImage, $left, $bottom );
	}
	if( ref( $oImage ) ne 'ImageContent' ){
		croak( "showImage must be given an ImageContent object to show" );
	}
	$this->showXObject( $oImage, $left, $bottom, $attr );
}

sub showXObject {
	my( $this, $oImage, $left, $bottom, $attr ) = @_;
	if( ref( $bottom ) eq 'ImageContent' || ref( $bottom ) eq 'XObject' ){
		( $left, $bottom, $oImage ) = ( $oImage, $left, $bottom );
	}
	unless( ref( $oImage ) eq 'ImageContent' || ref( $oImage ) eq 'XObject' ){
		croak( "showXObject must be given an ImageContent or XObject to show" );
	}
	my @xmls = ( qq{Name="$oImage->{Name}"}, qq{Left="$left"}, qq{Bottom="$bottom"} );
	$left = &PDF::tellSize( $left );
	$bottom = &PDF::tellSize( $bottom );
	my @translate = ( 1, 0, 0, 1, $this->{Container}->{Left} + $left, $this->{Container}->{Bottom} + $bottom );
	my( $w, $h ) = ( $oImage->{DisplayWidth}, $oImage->{DisplayHeight} );
	if( $attr->{Scale} ){
		$w *= $attr->{Scale};
		$h *= $attr->{Scale};
		push( @xmls, qq{Scale="$attr->{Scale}"} );
	} else {
		if( $attr->{ScaleX} ){ $w *= $attr->{ScaleX}; push( @xmls, qq{ScaleX="$attr->{ScaleX}"} ); }
		if( $attr->{ScaleY} ){ $h *= $attr->{ScaleY}; push( @xmls, qq{ScaleY="$attr->{ScaleY}"} ); }
		if( $attr->{Width} ){
			if( $attr->{Width} =~ /([\d\.]+)%/ ){
				$w = $1 * $this->{Container}->{Width} / 100;
			} else {
				$w = &PDF::tellSize( $attr->{Width} );
			}
			push( @xmls, qq{Width="$attr->{Width}"} );
			if( !$attr->{Height} ){
				$h = $w / $oImage->{Width} * $oImage->{Height};
			}
		}
		if( $attr->{Height} ){
			if( $attr->{Height} =~ /([\d\.]+)%/ ){
				$h = $1 * $this->{Container}->{Height} / 100;
			} else {
				$h = &PDF::tellSize( $attr->{Height} );
			}
			push( @xmls, qq{Height="$attr->{Height}"} );
			if( !$attr->{Width} ){
				$w = $h * $oImage->{Width} / $oImage->{Height};
			}
		}
	}
	my @scale = ( $w, 0, 0, $h, 0, 0 );
	if( !$attr->{Rotation} && ( defined $attr->{Href} || defined $attr->{Anchor} ) ){
		# Href would not be exported to XML because the Annot will do this.
		my $rect = new Rect( $this->{Container}->{Left} + $left, $this->{Container}->{Bottom} + $bottom );
		$attr->{Flip} ||= 0;
		if( $attr->{Flip} == 1 || $attr->{Flip} == 2 ){
			$rect->width( $h );
			$rect->height( $w );
		} else {
			$rect->width( $w );
			$rect->height( $h );
		}
		if( defined $attr->{Anchor} ){
			# If anchor is defined, the position "left" and "bottom" must be invalidated.
			$translate[4] -= $rect->{Left};
			$translate[5] -= $rect->{Bottom};
			$rect->moveBy( 0 - $rect->{Left}, 0 - $rect->{Bottom} );
			push( @xmls, qq{Anchor="$attr->{Anchor}"} );
			my $v = $Rect::Anchors{ $attr->{Anchor} } || 30;	# Bottom-left corner
			my( $cw, $ch ) = ( $this->{Container}->{Width}, $this->{Container}->{Height} );
			if( $v % 10 == 1 ){	# North, Center, South
				$rect->moveBy( ( $cw - $rect->{Width} ) / 2, 0 );
				$translate[4] += ( $cw - $rect->{Width} ) / 2;
			} elsif( $v % 10 == 2 ){	# NorthEast, East, SouthEast
				$rect->moveBy( $cw - $rect->{Width}, 0 );
				$translate[4] += $cw - $rect->{Width};
			}
			if( int( $v / 10 ) == 2 ){	# West, Center, East
				$rect->moveBy( 0, ( $ch - $rect->{Height} ) / 2 );
				$translate[5] += ( $ch - $rect->{Height} ) / 2;
			} elsif( int( $v / 10 ) == 1 ){	# NorthWest, North, NorthEast
				$rect->moveBy( 0, $ch - $rect->{Height} );
				$translate[5] += $ch - $rect->{Height};
			}
		}
		if( defined $attr->{Href} ){
			new Annot( $rect, 'Link', { 'URI'=>$attr->{Href}, 'Border'=>'None', 'Auto' => 1 } );
		}
	}
	my( $t, $alpha, $beta ) = ( 0 ) x 3;
	if( $attr->{Rotation} ){
		push( @xmls, qq{Rotation="$attr->{Rotation}"} );
		$t = $attr->{Rotation} * 3.1416 / 180;
	}
	if( defined $attr->{Flip} ){
		push( @xmls, qq{Flip="$attr->{Flip}"} ) if( defined $attr->{Flip} );
		if( $attr->{Flip} == 1 ){
			$translate[4] += $h;
			$scale[0] = $w;
			$scale[3] = $h;
			$t = 3.1416 / 2;
		} elsif( $attr->{Flip} == 2 ){
			$translate[5] += $w;
			$scale[0] = $w;
			$scale[3] = $h;
			$t = 3.1416 / (-2);
		} elsif( $attr->{Flip} == 3 ){
			$translate[4] += $w;
			$translate[5] += $h;
			$t = 3.1416;
		}
	}
	if( ref( $oImage ) eq 'XObject' ){
		$scale[0] /= $oImage->{Width};
		$scale[3] /= $oImage->{Height};
	}
	my $cosval = cos( $t );
	my $sinval = sin( $t );
	if( defined $attr->{SkewY} ){
		push( @xmls, qq{SkewY="$attr->{SkewY}"} );
		$alpha = sin( $attr->{SkewY} * 3.1416 / 180 ) / cos( $attr->{SkewY} * 3.1416 / 180 );
	}
	if( defined $attr->{SkewX} ){
		push( @xmls, qq{SkewX="$attr->{SkewX}"} );
		$beta = sin( $attr->{SkewX} * 3.1416 / 180 ) / cos( $attr->{SkewX} * 3.1416 / 180 );
	}
	my @rotate = ( $cosval, $sinval, 0 - $sinval, $cosval, 0, 0 );
	my @skew = ( 1, $alpha, $beta, 1, 0, 0 );
	my @mirror = ( 1, 0, 0, 1, 0, 0 );
	if( defined $attr->{Mirror} ){
		if( $attr->{Mirror} eq 'X' ){ $mirror[0] = -1; } elsif( $attr->{Mirror} eq 'Y' ){ $mirror[3] = -1; }
		push( @xmls, qq{Mirror="$attr->{Mirror}"} );
	}
	$this->{Stream} .= sprintf( "q %.4f %.4f %.4f %.4f %.4f %.4f cm$GraphContent::endln",
		$this->transform( $this->transform( $this->transform( $this->transform( @scale, @mirror ), @skew ), @rotate ), @translate ) );
	$this->{Stream} .= join( ' ', qq{/$oImage->{Name}}, 'Do', 'Q', $GraphContent::endln );
	push( @{$this->{XML}}, join( ' ', ( ref( $oImage ) eq 'XObject'? '<ShowXObject': '<ShowImage' ),
		@xmls, '/>' ) ) unless( @{$this->{CallStack}} );
	$this->{Resources}->{XObject}->{ $oImage->{Name} } = 1;
	push( @{$this->{XObject}}, $oImage );
}

sub showInlineImage { 
	my( $this, $oImage, $left, $bottom ) = @_;
	$left = &PDF::tellSize( $left );
	$bottom = &PDF::tellSize( $bottom );
	if( ref( $oImage ) ne 'ImageContent' ){
		croak( "showInlineImage must be given an ImageContent object to show" );
	}
	my @trans = ( $oImage->{DisplayWidth}, 0, 0, $oImage->{DisplayHeight}, $this->{Container}->{Left} + $left, $this->{Container}->{Bottom} + $bottom );
	$this->{Stream} .= join( ' ', 'q', @trans, 'cm', $oImage->makeInlineCode( ), 'Q', $GraphContent::endln );
}

# Show a **short** text, but multiline permissible
sub showText {
	my( $this, $x, $y, $text, $attr ) = @_;
	my @xmls = ( qq{X="$x"}, qq{Y="$y"} );
	push( @xmls, sprintf( qq{Text="%s"}, &PDF::escXMLChar( $text ) ) );
	push( @{$this->{CallStack}}, 1 );
	for( qw(Align Encoding FontFace FontSize Leading Color BorderColor BorderWidth BorderDash Outline Width Height FitWidth FitHeight Rotation SkewX SkewY Mirror) ){
		next unless( defined $attr->{$_} );
		push( @xmls, qq{$_="$attr->{$_}"} );
	}
	if( exists $PDF::root->{Prefs}->{ReplaceEntities} && $PDF::root->{Prefs}->{ReplaceEntities} ){
		my $CharTable = \%PDFFont::WinAnsiChars;
		my $encoding = $attr->{Encoding} || $PDF::root->{Prefs}->{Encoding};
		if( $encoding eq 'PDFDocEncoding' ){ $CharTable = \%PDFFont::PDFDocChars; }
		elsif( $encoding eq 'MacRomanEncoding' ){ $CharTable = \%PDFFont::MacRomanChars; }
		elsif( $encoding eq 'StandardEncoding' ){ $CharTable = \%PDFFont::StandardChars; }
		$text =~ s/(?<!\\)&(\w+);/chr($CharTable->{$1})/ge;
	}
	$text =~ s/(^\s+)|(\s+$)//gm;
	$x = &PDF::tellSize( $x );
	$y = &PDF::tellSize( $y );
	my $w = &PDF::tellSize( $attr->{Width} );
	my $h = &PDF::tellSize( $attr->{Height} );
	my $fs = $attr->{FontSize} || 12;	# Font size
	my $tl = $attr->{Leading} || $attr->{FontSize} || 12;	# Line height. Could be change by vertical fitting
	# Now preprocess text. Break the text into lines.
	my $oFont = $PDF::root->getFont( $attr->{FontFace} || 'Helvetica' );
	my @lines = grep { !/^$/ } split( /\s*[\n\r]+\s*/, $text );
	my $tz = 100;	# Font scaling factor
	my $el = 0;		# When doing vertical fit by changing line height, the first point must be elevated because the spacing is above the text.
	# Now adjust line height or font size.
	if( $attr->{Height} ){
		my $method = $attr->{FitHeight};
		if( $method eq 'LineHeight' ){	# Adjust line height only for mutli-line text
			if( scalar @lines > 1 ){
				$tl = ( $h - $fs ) / ( scalar @lines - 1 );
				$el = $tl - $fs;
			} else {
				$method = 'Stretch';	# One-liners must be stretched to fit
			}
		}
		if( $method eq 'Stretch' ){
			my $newfs = $h / scalar @lines;
			$tl = $newfs;
			$tz *= ( $fs / $newfs );
			$fs = $newfs;
		}
	}
	my @linewids = map { $oFont->getWordWidth( $_, $fs ) * $tz / 100 } @lines;
	$this->saveGState( );
	$this->setLineWidth( &PDF::tellSize( $attr->{BorderWidth} ) || 0.5 );
	if( exists $attr->{BorderDash} && $attr->{BorderDash} ){
		$this->setDash( $attr->{BorderDash} );
	}
	$this->{Stream} .= sprintf( "BT /%s %.4f Tf 0 Tc 0 Tw $GraphContent::endln", $oFont->{Name}, $fs );
	my $cosval = defined $attr->{Rotation}? cos( $attr->{Rotation} * 3.1416 / 180 ): 1;
	my $sinval = defined $attr->{Rotation}? sin( $attr->{Rotation} * 3.1416 / 180 ): 0;
	my $alpha = defined $attr->{SkewY}? sin( $attr->{SkewY} * 3.1416 / 180 ) / cos( $attr->{SkewY} * 3.1416 / 180 ): 0;
	my $beta = defined $attr->{SkewX}? sin( $attr->{SkewX} * 3.1416 / 180 ) / cos( $attr->{SkewX} * 3.1416 / 180 ): 0;
	my @mirror = ( 1, 1 );
	if( defined $attr->{Mirror} ){
		if( $attr->{Mirror} eq 'X' ){ $mirror[0] = -1; } elsif( $attr->{Mirror} eq 'Y' ){ $mirror[1] = -1; }
	}
	$this->{Stream} .= sprintf( "%.4f %.4f %.4f %.4f %.4f %.4f Tm $GraphContent::endln %.4f TL $GraphContent::endln",
		$mirror[0] * ( $cosval - $sinval * $alpha ), $mirror[0] * ( $sinval + $cosval * $alpha ),
		$mirror[1] * ( $cosval * $beta - $sinval ), $mirror[1] * ( $sinval * $beta + $cosval ),
		$this->{Container}->left( ) + $x, $this->{Container}->bottom( ) + $y, $tl );
	if( $el ){
		$this->{Stream} .= qq{0 $el Td };
	}
	my $rendermode = 0;
	$this->setColor( $attr->{Color}, 1 ) if( $attr->{Color} );
	if( defined $attr->{BorderColor} ){
		$this->setColor( $attr->{BorderColor} );
		$rendermode = ( $attr->{Outline}? 1: 2 );
	}
	if( $attr->{Texture} && ref( $attr->{Texture} ) eq 'PDFTexture' ){
		push( @xmls, qq{Texture="$attr->{Texture}->{Name}"} );
		$this->setTexture( $attr->{Texture}, 1 );
	}
	if( $attr->{Shading} && ref( $attr->{Shading} ) eq 'PDFShading' ){
		push( @xmls, qq{Shading="$attr->{Shading}->{Name}"} );
		$rendermode = 5;	# Stroke and add to clip path
	}
	if( $rendermode ){
		$this->{Stream} .= qq{$rendermode Tr };
	}
	for my $i ( 0..$#lines ){
		next if( !$linewids[$i] );
		my $lineoffset = 0;
		if( $attr->{Width} ){
			my $method = $attr->{FitWidth};
			$this->{Stream} .= sprintf( "%.2f Tz ", $tz );
			# Note below that Tc and Tw are affected by Tz
			if( $method eq '' || $method eq 'None' ){
				if( $attr->{Align} eq 'Center' ){
					$this->{Stream} .= sprintf( "%.4f 0 Td ", ( $lineoffset = ( $w - $linewids[$i] ) / 2 ) );
				} elsif( $attr->{Align} eq 'Right' ){
					$this->{Stream} .= sprintf( "%.4f 0 Td ", ( $lineoffset = $w - $linewids[$i] ) );
				}
			}
			if( $method eq 'WordSpacing' ){
				my @count = ( $lines[$i] =~ m/ /g );
				if( scalar @count ){
					$this->{Stream} .= sprintf( "0 Tc %.2f Tz %.4f Tw ", $tz, ( $w - $linewids[$i] ) / ( scalar @count ) * 100 / $tz );
				} else {
					$method = 'CharSpacing';	# Continue to use character spacing method
				}
			}
			if( $method eq 'CharSpacing' ){
				if( length( $lines[$i] ) > 1 ){
					$this->{Stream} .= sprintf( "0 Tw %.2f Tz %.4f Tc ", $tz, ( $w - $linewids[$i] ) / ( length( $lines[$i] ) - 1 ) * 100 / $tz );
				} else {
					$method = 'CharScaling';	# Continue to use character scaling method
				}
			}
			if( $method eq 'CharScaling' ){
				$this->{Stream} .= sprintf( "0 Tw 0 Tc %.2f Tz ", $tz * $w / $linewids[$i] );
			}
		}
		$lines[$i] = &PDF::escStr( $lines[$i] );
		$this->{Stream} .= qq{($lines[$i]) ' };
		if( $lineoffset ){
			$this->{Stream} .= sprintf( "%.4f 0 Td ", 0 - $lineoffset );
		}
	}
	$this->{Stream} .= 'ET ';
	if( $attr->{Shading} && ref( $attr->{Shading} ) eq 'PDFShading' ){
		my $rect = new Rect( $x, $y );
		$rect->width( &PDF::max( $w, @linewids ) );
		$rect->height( &PDF::max( $h, $fs * scalar( @lines ) * 1.2 ) );	# Makeshift; will be changed in the future.
		$rect->moveBy( $this->{Container}->left( ), $this->{Container}->bottom( ) - $rect->height( ) );
		$this->intersect( );
		$this->closePath( );
		$this->gradFill( $attr->{Shading}, $rect );
	}
	$this->restoreGState( );
	pop( @{$this->{CallStack}} );
	$this->{Resources}->{Font}->{ $oFont->{Name} } = 1;
	push( @{$this->{XML}}, join( ' ', '<ShowText', @xmls, '/>' ) ) unless( @{$this->{CallStack}} );
}

# Show a line of text on a circular arc
sub showBanner {
	my( $this, $x, $y, $text, $r, $attr ) = @_;
	my @xmls = ( qq{X="$x"}, qq{Y="$y"} );
	push( @xmls, sprintf( qq{Text="%s"}, &PDF::escXMLChar( $text ) ), qq{Radius="$r"} );
	push( @{$this->{CallStack}}, 1 );
	for( qw(FromAngle ToAngle Encoding FontFace FontSize Leading Color BorderColor BorderWidth BorderDash Outline Rotation SkewX SkewY) ){
		next unless( defined $attr->{$_} );
		push( @xmls, qq{$_="$attr->{$_}"} );
	}
	my $from = ( defined $attr->{ToAngle}? $attr->{FromAngle}: 180 ) * 3.1416 / 180;
	my $to = ( defined $attr->{ToAngle}? $attr->{ToAngle}: 0 ) * 3.1416 / 180;
	$x = &PDF::tellSize( $x );
	$y = &PDF::tellSize( $y );
	$r = &PDF::tellSize( $r );
	my( $origx, $origy ) = ( $x + $r * cos( $from - 3.1416 ), $y + $r * sin( $from - 3.1416 ) );
	my $fs = $attr->{FontSize} || 12;
	my $tl = $attr->{Leading} || 12;
	my $rr = $r + $tl * 1.5;	# Make the radius slightly larger
	my $oFont = $PDF::root->getFont( $attr->{FontFace} || 'Helvetica' );
	my $dir = ( $to > $from )? 1: -1;
	my $tz = ( $attr->{CharScaling} || 100 );
	$this->saveGState( );
	$this->{Stream} .= qq{ BT /$oFont->{Name} $fs Tf $GraphContent::endln};
	my $rendermode = 0;
	$this->setColor( $attr->{Color}, 1 ) if( $attr->{Color} );
	if( defined $attr->{BorderColor} ){
		$this->setColor( $attr->{BorderColor} );
		$rendermode = ( $attr->{Outline}? 1: 2 );
	}
	$this->setLineWidth( &PDF::tellSize( $attr->{BorderWidth} ) || 0.5 );
	if( exists $attr->{BorderDash} && $attr->{BorderDash} ){
		$this->setDash( $attr->{BorderDash} );
	}
	if( $attr->{Texture} && ref( $attr->{Texture} ) eq 'PDFTexture' ){
		push( @xmls, qq{Texture="$attr->{Texture}->{Name}"} );
		$this->setTexture( $attr->{Texture}, 1 );
	}
	if( $attr->{Shading} && ref( $attr->{Shading} ) eq 'PDFShading' ){
		push( @xmls, qq{Shading="$attr->{Shading}->{Name}"} );
		$rendermode = 5;	# Stroke and add to clip path
	}
	if( $rendermode ){
		$this->{Stream} .= qq{$rendermode Tr };
	}
	my( $alpha, $beta ) = ( 0, 0 );
	if( defined $attr->{SkewY} ){
		$alpha = sin( $attr->{SkewY} * 3.1416 / 180 ) / cos( $attr->{SkewY} * 3.1416 / 180 );
	}
	if( defined $attr->{SkewX} ){
		$beta = sin( $attr->{SkewX} * 3.1416 / 180 ) / cos( $attr->{SkewX} * 3.1416 / 180 );
	}
	my @lines = split( /[\n\r]+/, $text );
	for( @lines ){
		my @chars = split( // );
		next if( !@chars );
		my $angle = $from;
		# Care must be taken so that the top boundary of a character is tangent to the circle at the middle, not the left.
		my @spans = ( );	# Character span angle
		my @cwids = ( );	# Character width
		my $total = 0;
		for( @chars ){
			my $w = $oFont->getCharWidth( $_, $fs );
			my $t = atan2( $w * $fs / 1000, $r );
			push( @cwids, $w );
			push( @spans, $t );
			$total += $t;
		}
		my $sp = ( @chars > 1? ( abs( $to - $angle ) - $total ) / ( @chars - 1 ): 0 );
		foreach my $c ( @chars ){
			my $span = shift( @spans );
			my $cosval = cos( $angle - 3.1416 / 2 + ( $attr->{Rotation} || 0 ) * 3.1416 / 180 );
			my $sinval = sin( $angle - 3.1416 / 2 + ( $attr->{Rotation} || 0 ) * 3.1416 / 180 );
			$c = &PDF::escStr( $c );
			my $w = shift( @cwids ) * $fs / 1000 / 2;
			$this->{Stream} .= sprintf( "%.4f %.4f %.4f %.4f %.4f %.4f Tm %.2f Tz (%s) Tj $GraphContent::endln",
				$cosval - $sinval * $alpha, $sinval + $cosval * $alpha, $cosval * $beta - $sinval, $sinval * $beta + $cosval,
				$this->{Container}->left( ) + $origx + $r * cos( $angle - $span / 2 ) - $w * sin( $angle - $span / 2 ),
				$this->{Container}->bottom( ) + $origy + $r * sin( $angle - $span / 2 ) + $w * cos( $angle - $span / 2 ), $tz, $c );
			$angle += ( ( $spans[0] || 0 ) / 2 + $span / 2 + $sp ) * $dir;
		}
		$r -= $tl;
	}
	$this->{Stream} .= qq{ET$GraphContent::endln};
	if( $rendermode == 5 ){	# Apply gradient fill
		$this->gradFill( $attr->{Shading}, new Rect( $origx - $rr, $origy - $rr, $origx + $rr, $origy + $rr ) );
	}
	$this->restoreGState( );
	$this->{Stream} .= qq{$GraphContent::endln};
	pop( @{$this->{CallStack}} );
	$this->{Resources}->{Font}->{ $oFont->{Name} } = 1;
	push( @{$this->{XML}}, join( ' ', '<ShowBanner', @xmls, '/>' ) ) unless( @{$this->{CallStack}} );
}

# Draw a fixed-size POSTNET barcode
sub drawPostnet {
	my( $this, $x, $y, $zip, $dp, $cc ) = @_;	# Zip+4, delivery point, check digit
	unless( @{$this->{CallStack}} ){
		my @xml = ( qq{Type="Postnet" X="$x" Y="$y"} );
		defined $dp && push( @xml, qq{Dest="$dp"} );
		push( @{$this->{XML}}, join( ' ', '<DrawCustom', @xml, '/>' ) );
	}
	push( @{$this->{CallStack}}, 1 );
	$zip ||= '00000';
	$dp ||= '';
#	$zip =~ s/[^0-9]//g;
#	$dp =~ s/[^0-9]//g;
	$x = &PDF::tellSize( $x );
	$y = &PDF::tellSize( $y );
	my @codes = ( '11000', '00011', '00101', '00110', '01001', '01010', '01100', '10001', '10010', '10100' );
	my @digits = grep{ /\d/ } split( //, $zip . $dp );
	if( !defined $cc || $cc !~ /^\d$/ ){
		$cc = 0;
		map { $cc += $_; } @digits;
		push( @digits, substr( 10 - $cc % 10, -1, 1 ) );
	} else {
		push( @digits, $cc );
	}
	my $bar = '1';
	map { $bar .= $codes[$_]; } @digits;
	$bar .= '1';
	my @bars = split( //, $bar );
	my( $oldx, $oldy ) = ( $this->{x} - $this->{Container}->left( ), $this->{y} - $this->{Container}->bottom( ) );
	$this->saveGState( );
	$this->setLineWidth( 1.44 );
	$this->setLineCap( 'Butt' );
	for( @bars ){
		$this->moveTo( $x, $y );
		$this->connectTo( $x, $y + ( $_? 9: 3.6 ) );
		$x += 3.6;
	}
	$this->stroke( );
	$this->restoreGState( );
	pop( @{$this->{CallStack}} );
}

# Draw a FIM barcode for use on envelopes
sub drawFIM {
	my( $this, $x, $y, $type ) = @_;
	push( @{$this->{XML}}, qq{<DrawCustom Type="FIM" X="$x" Y="$y" FIMType="$type" />} ) unless( @{$this->{CallStack}} );
	push( @{$this->{CallStack}}, 1 );
	$x = &PDF::tellSize( $x );
	$y = &PDF::tellSize( $y );
	my %fims = ( 'A' => '110010011', 'B' => '101101101', 'C' => '110101011' );	# FIM A, B, C
	my @bars = split( //, $fims{ $type } );
	my( $oldx, $oldy ) = ( $this->{x} - $this->{Container}->left( ), $this->{y} - $this->{Container}->bottom( ) );
	$this->saveGState( );
	$this->setLineWidth( 2.25 );
	$this->setLineCap( 'Butt' );
	for( @bars ){
		if( $_ ){
			$this->moveTo( $x, $y );
			$this->connectTo( $x, $y + 45 );
		}
		$x += 4.5;
	}
	$this->stroke( );
	$this->restoreGState( );
	pop( @{$this->{CallStack}} );
}

sub showListImage {
	my( $this, $img, $text, $offset ) = @_;		# $text is a TextContent object!
	return unless( ref( $text ) eq 'TextContent' || ref( $text ) eq 'FloatingText' );
	my @locs = $text->getParaPos( $img, $offset );
	for( @locs ){
		$this->showImage( $img, $_->[0] - $this->{Container}->left( ), $_->[1] - $this->{Container}->bottom( ),
		{ 'Rotation'=>( $text->{TextDir}? [ 0, 90, -90, 180 ]->[ $text->{TextDir} ]: ( $text->{Rotation} * 180 / 3.1416 ) ) } );
	}
}

%GraphContent::GDIFuncs = (
	0x0052 => 'AbortDoc',
	0x0436 => 'AnimatePalette',
	0x0817 => 'Arc',	# int x1, x2, y1, y2, x3, y3, x4, y4
	0x0922 => 'BitBlt',
	0x0830 => 'Chord',	# int x1, x2, y1, y2, x3, y3, x4, y4
	0x06FE => 'CreateBitmap',
	0x02FD => 'CreateBitmapIndirect',
	0x00F8 => 'CreateBrush',
	0x02FC => 'CreateBrushIndirect',
	0x02FB => 'CreateFontIndirect',
	0x00F7 => 'CreatePalette',
	0x01F9 => 'CreatePatternBrush',
	0x02FA => 'CreatePenIndirect',
	0x06FF => 'CreateRegion',
	0x01F0 => 'DeleteObject',
	0x01f0 => 'DeleteObject',
	0x0940 => 'DibBitblt',
	0x0142 => 'DibCreatePatternBrush',
	0x0B41 => 'DibStretchBlt',
	0x062F => 'DrawText',
	0x0418 => 'Ellipse',	# int left, top, right, bottom
	0x005E => 'EndDoc',
	0x0050 => 'EndPage',
	0x0626 => 'Escape',
	0x0415 => 'ExcludeClipRect',
	0x0548 => 'ExtFloodFill',
	0x0A32 => 'ExtTextOut',
	0x0228 => 'FillRegion',
	0x0419 => 'FloodFill',
	0x0429 => 'FrameRegion',
	0x0416 => 'IntersectClipRect',
	0x012A => 'InvertRegion',
	0x0213 => 'LineTo',	# int x, y
	0x0214 => 'MoveTo',	# int x, y
	0x0220 => 'OffsetClipRgn',
	0x0211 => 'OffsetViewportOrg',
	0x020F => 'OffsetWindowOrg',
	0x012B => 'PaintRegion',
	0x061D => 'PatBlt',
	0x081A => 'Pie',	# int x1, x2, y1, y2, x3, y3, x4, y4
	0x0324 => 'Polygon',
	0x0325 => 'Polyline',
	0x0538 => 'PolyPolygon',
	0x0035 => 'RealizePalette',
	0x041B => 'Rectangle',	# int x1, x2, y1, y2
	0x014C => 'ResetDc',
	0x0139 => 'ResizePalette',
	0x0127 => 'RestoreDC',
	0x061C => 'RoundRect',	# int x1, x2, y1, y2
	0x001E => 'SaveDC',
	0x0412 => 'ScaleViewportExt',
	0x0410 => 'ScaleWindowExt',
	0x012C => 'SelectClipRgn',
	0x012D => 'SelectObject',
	0x0234 => 'SelectPalette',
	0x0201 => 'SetBkColor',
	0x0102 => 'SetBkMode',
	0x0d33 => 'SetDibToDev',
	0x0103 => 'SetMapMode',
	0x0231 => 'SetMapperFlags',
	0x0037 => 'SetPalEntries',
	0x041F => 'SetPixel',
	0x0106 => 'SetPolyFillMode',
	0x0105 => 'SetRelabs',
	0x0104 => 'SetROP2',
	0x0107 => 'SetStretchBltMode',
	0x012E => 'SetTextAlign',
	0x0108 => 'SetTextCharExtra',
	0x0209 => 'SetTextColor',
	0x020A => 'SetTextJustification',
	0x020E => 'SetViewportExt',
	0x020D => 'SetViewportOrg',
	0x020C => 'SetWindowExt',
	0x020B => 'SetWindowOrg',
	0x014D => 'StartDoc',
	0x004F => 'StartPage',
	0x0B23 => 'StretchBlt',
	0x0F43 => 'StretchDIBits',
	0x0521 => 'TextOut',
);

$GraphContent::twip = 0.05;

%GDIFuncToPDF = (
	'CreateBrushIndirect' => sub {
		my $this = shift;
		my @parms = unpack( 'vC4v', shift );
		# S0 00 | RR GG | BB 00 | H0 00 - WORD lbStyle (0~5), COLORREF lbColor, short int lbHatch (0~5).
		$this->closePath( );
		$this->setColor( join( '', map { uc( unpack( 'H*', chr($_) ) ) } @parms[1..3] ), 1 );
	},
	'CreateFontIndirect' => sub {
		my $this = shift;
		my @parms = unpack( 's5C8A*', shift );
		$WMFFontFace = $parms[-1];
		$WMFFontFace =~ s/\W//g;
		$WMFFontSize = $parms[0] * $GraphContent::twip;
	},
	'CreatePenIndirect' => sub {
		my $this = shift;
		my @parms = unpack( 'vVC4', shift );	# WORD lbStyle, POINT lbWidth, COLORREF lbColor
		$this->closePath( );
		if( $parms[0] < 5 ){ $this->setDash( [ qw(Solid Dashed Dotted DashDot 111111110011001100) ]->[ $parms[0] ] ); }
		if( $parms[1] ){ $this->setLineWidth( $parms[1] * $GraphContent::twip ); }
		$this->setColor( join( '', map { uc( unpack( 'H*', chr($_) ) ) } @parms[2..4] ) );
	},
	'Ellipse' => sub {
		my $this = shift;
		my @parms = map { $_ * $GraphContent::twip } unpack( 's4', shift );	# Sequence: y2, x2, y1, x1
		$this->moveTo( ( $parms[1] + $parms[3] ) / 2, ( $parms[0] + $parms[2] ) / 2 );
		$this->drawEllipse( abs( $parms[1] - $parms[3] ) / 2, abs( $parms[0] - $parms[2] ) / 2, 0, 1 );
	},
	'ExtTextOut' => sub {
		my $this = shift;
		my $parm = shift;
		my ( $y, $x, $count ) = unpack( 'sss', substr( $parm, 0, 8 ) );
		my $text = pack( 'A*', substr( $parm, 8, $count ) );
		$this->showText( $x * $GraphContent::twip, $y * $GraphContent::twip - $WMFFontSize, $text, {'FontFace'=>$WMFFontFace, 'FontSize'=>$WMFFontSize, 'Color'=>$WMFTextColor, 'Mirror'=>'Y'} );
	},
	'LineTo' => sub {
		my $this = shift;
		my @parms = map { $_ * $GraphContent::twip } unpack( 's2', shift );
		$this->lineTo( $parms[1], $parms[0] );
	},
	'MoveTo' => sub {
		my $this = shift;
		my @parms = map { $_ * $GraphContent::twip } unpack( 's2', shift );
		$this->moveTo( $parms[1], $parms[0] );
	},
	'Pie' => sub {	# Needs debugging: arc is not shown at place
		my $this = shift;
		my @parms = map { $_ * $GraphContent::twip } unpack( 's8', shift );	# Sequence: y4, x4, y3, x3; y2, x2, y1, x1
		my( $x0, $y0 ) = ( ( $parms[5] + $parms[7] ) / 2, ( $parms[4] + $parms[6] ) / 2 );
		my( $a, $b ) = ( abs( $parms[5] - $parms[7] ) / 2, abs( $parms[4] - $parms[6] ) / 2 );
		my( $from, $to );
		if( $parms[1] - $x0 == 0 ){ $to = 180 + 90 * ( $parms[0] - $y0 > 0? -1: 1 ); } else { $to = atan2( $parms[1] - $y0, $parms[0] - $x0 ); }
		if( $parms[3] - $x0 == 0 ){ $from = 180 + 90 * ( $parms[2] - $y0 > 0? -1: 1 ); } else { $from = atan2( $parms[3] - $y0, $parms[2] - $x0 ); }
		if( $from < $to ){ ( $from, $to ) = ( $to, $from ); }
		$this->moveTo( $x0, $y0 );
		$this->drawOvalArc( $a, $b, $from, $to, 1 );
	},
	'Polygon' => sub {
		my $this = shift;
		my $parm = substr( shift, 2 );	# count
		$this->drawPolyLine( 1, map { $_ * $GraphContent::twip } unpack( 's*', $parm ) );
	},
	'Polyline' => sub {
		my $this = shift;
		my $parm = substr( shift, 2 );	# count
		$this->setLineWidth( 0.5 );
		$this->drawPolyLine( 0, map { $_ * $GraphContent::twip } unpack( 's*', $parm ) );
	},
	'PolyPolygon' => sub {
		my $this = shift;
		my $parm = shift;
		my $count = unpack( 's', $parm );
		my @polys = unpack( 's*', substr( $parm, 2, $count * 2 ) );
		substr( $parm, 0, $count * 2 + 2 ) = '';
		$this->setLineWidth( 0.5 );
		for my $poly ( @polys ){
			$this->drawPolyLine( 1, map { $_ * $GraphContent::twip } unpack( 's*', substr( $parm, 0, $poly * 4, '' ) ) );
		}
	},
	'Rectangle' => sub {
		my $this = shift;
		my @parms = map { $_ * $GraphContent::twip } unpack( 's4', shift );	# Sequence: b, r, t, l
		$this->drawRectAt( new Rect( $parms[3], $parms[0], $parms[1], $parms[2] ), 1 );
	},
	'RoundRect' => sub {
		my $this = shift;
		my @parms = map { $_ * $GraphContent::twip } unpack( 's6', shift );	# Sequence: h, w, b, r, t, l
		$this->drawRoundedRectAt( new Rect( $parms[5], $parms[2], $parms[3], $parms[4] ), ( $parms[0] + $parms[1] ) / 4, 1 );	# Use average radius
	},
	'SetTextColor' => sub {
		my $this = shift;
		$WMFTextColor = unpack( "H*", substr( shift, 0, 3 ) );
	},
);

sub showWMF {
	my( $this, $file, $left, $top, $attr ) = @_;
	my @xmls = ( qq{File="$file"}, qq{Left="$left"}, qq{Top="$top"} );
	$left = &PDF::tellSize( $left );
	$top = &PDF::tellSize( $top );
	my( $scalex, $scaley ) = ( 1, 1 );
	for( qw(Scale ScaleX ScaleY) ){
		defined $attr->{$_} && push( @xmls, qq{$_="$attr->{$_}"} );
	}
	if( $attr->{Scale} ){
		$scalex = $attr->{Scale};
		$scaley = $attr->{Scale};
	} else {
		if( $attr->{ScaleX} ){ $scalex = $attr->{ScaleX}; }
		if( $attr->{ScaleY} ){ $scaley = $attr->{ScaleY}; }
	}
	push( @{$this->{CallStack}}, 1 );
	my( $chunk, $ImgData, $parms, @AldusHeader, @WmfHeader );
	$file = &PDF::secureFileName( $file );
	my $fh = new FileHandle( );
	open( $fh, "<$file" ) or croak "Can't open file $file";
	binmode $fh;
	while( read( $fh, $chunk, 2048 ) ){
		$ImgData .= $chunk;
	}
	close( $fh );
	$this->saveGState( );
	$this->{Stream} .= sprintf( "%.4f 0 0 %.4f %.4f %.4f cm$GraphContent::endln", $scalex, -1 * $scaley, $this->{Container}->{Left} + $left, $this->{Container}->{Bottom} + $top );
	if( unpack( 'V', substr( $ImgData, 0, 4 ) ) == 2596720087 ){	# 0x9AC6CDD7: Placeable metafile signature
		@AldusHeader = unpack( 'VvssssvVv', substr( $ImgData, 0, 22, '' ) );
	}
	@WmfHeader = unpack( 'vvvVvVv', substr( $ImgData, 0, 18, '' ) );
	while( length( $ImgData ) ){
		my ( $size, $type ) = unpack( 'Vv', substr( $ImgData, 0, 6, '' ) );
		if( $size > 3 ){
			$parms = substr( $ImgData, 0, $size * 2 - 6, '' );
		}
		last if( !$type );
		if( defined $GDIFuncToPDF{ $GDIFuncs{$type} } ){
			&{$GDIFuncToPDF{ $GDIFuncs{$type} }}( $this, $parms );
		}
	}
	$this->restoreGState( );
	pop( @{$this->{CallStack}} );
	push( @{$this->{XML}}, join( ' ', '<ShowWMF', @xmls, '/>' ) ) unless( @{$this->{CallStack}} );
}

sub startXML {
	my( $this, $dep ) = @_;
	# If this is a copy created from a template, then no code should be generated.
	return if( $this->{IsCopy} );
	print "\t" x $dep, '<Graph Rect="',
		join( ', ', $this->{Container}->left( ), $this->{Container}->bottom( ),
			$this->{Container}->right( ), $this->{Container}->top( ) ), '"';
	print q{ IsTemplate="1"} if( $this->{IsTemplate} );
	print qq{ BlendMode="$this->{BlendMode}"} if( defined $this->{BlendMode} );
	print qq{ Opacity="$this->{Opacity}"} if( defined $this->{Opacity} );
	print qq{ ZIndex="$this->{ZIndex}"} if( $this->{ZIndex} );
	print qq{ Name="$this->{Name}">\n};
	for( @{$this->{XML}} ){
		print "\t" x ( $dep + 1 ), $_, "\n";
	}
}

sub endXML {
	my( $this, $dep ) = @_;
	return if( $this->{IsCopy} );
	print "\t" x $dep, "</Graph>\n";
}

sub execXML {
	my ( $this, $kid ) = @_;	# $kid must be an XML tag OR a parsed object (internal use only).
	if( !ref( $kid ) ){
		push( @{$this->{XML}}, $kid );
		push( @{$this->{CallStack}}, 1 );
		$kid = ( new XML::Parser( Style=>'Objects' ) )->parse( $kid )->[0];
	}
	my $cmd = ref( $kid );
	$cmd =~ s/^(\w+::)+//;	# Reveal bare tag names
	return if( $cmd eq 'Characters' );
	bless $kid, 'HASH';
	if( $cmd eq 'MoveTo' ){
		$this->moveTo( $kid->{X}, $kid->{Y} );
	} elsif( $cmd eq 'Set' ){
		defined $kid->{Color} && $this->setColor( $kid->{Color}, ( $kid->{Ground} || 0 ), ( $kid->{ColorSpace} || undef ) );
		defined $kid->{Dash}  && $this->setDash( $kid->{Dash} );
		defined $kid->{LineWidth} && $this->setLineWidth( $kid->{LineWidth} );
		defined $kid->{Texture} && $this->setTexture( &PDF::getObjByName( $kid->{Texture} ), ( $kid->{Ground} || 0 ), ( $kid->{Color} || undef ) );
		defined $kid->{ColorSpace} && !defined $kid->{Color} && $this->setColorSpace( $kid->{ColorSpace} );	# Note the difference.
		defined $kid->{LineCap} && $this->setLineCap( $kid->{LineCap} );
		defined $kid->{LineJoin} && $this->setLineJoin( $kid->{LineJoin} );
		defined $kid->{MiterLimit} && $this->setMiterLimit( $kid->{MiterLimit} );
	} elsif( $cmd eq 'Exec' ){
		if( $kid->{Cmd} eq 'NewPath' ){
			$this->newPath( );
		} elsif( $kid->{Cmd} eq 'ClosePath' ){
			$this->closePath( );
		} elsif( $kid->{Cmd} eq 'CloseSubPath' ){
			$this->closeSubPath( );
		} elsif( $kid->{Cmd} eq 'Intersect' ){
			$this->intersect( $kid->{Eof} || 0 );
		} elsif( $kid->{Cmd} eq 'Fill' ){
			$this->fill( $kid->{Eof} );
		} elsif( $kid->{Cmd} eq 'Stroke' ){
			$this->stroke( );
		} elsif( $kid->{Cmd} eq 'StrokeFill' ){
			$this->strokeFill( $kid->{Eof} || 0 );
		} elsif( $kid->{Cmd} eq 'SaveGState' ){
			$this->saveGState( );
		} elsif( $kid->{Cmd} eq 'RestoreGState' ){
			$this->restoreGState( );
		}
	} elsif( $cmd eq 'Fill' ){
		$this->gradFill( &PDF::getObjByName( $kid->{Shading} ), new Rect( split( /,\s*/, $kid->{Rect} ) ), ( $kid->{ApplyOnly} || 0 ) );
	} elsif( $cmd eq 'LineTo' ){
		if( defined $kid->{Arrow} ){
			my @arrow = split( /,\s*/, $kid->{Arrow} );
			$this->lineTo( $kid->{X}, $kid->{Y}, { 'Arrow'=>\@arrow, 'Width'=>$kid->{Width}, 'Color'=>$kid->{Color}, 'PathOnly'=>$kid->{PathOnly} } );
		} else {
			for( qw(Width Color PathOnly) ){ $kid->{$_} ||= undef; }
			$this->lineTo( $kid->{X}, $kid->{Y}, $kid->{Width}, $kid->{Color}, $kid->{PathOnly} );
		}
	} elsif( $cmd eq 'CurveTo' ){
		my @coords = split( /,\s*/, $kid->{Coords} );
		$this->curveTo( ( $kid->{Type} || 0 ), @coords );
	} elsif( $cmd eq 'PolyLine' ){
		my @coords = split( /,\s*/, $kid->{Coords} );
		$this->drawPolyLine( ( $kid->{Fill} || 0 ), @coords );
	} elsif( $cmd eq 'DrawRect' ){
		for( qw(Round Fill Centered) ){ $kid->{$_} ||= 0; }
		if( $kid->{Round} ){
			$this->drawRoundedRect( $kid->{Width}, $kid->{Height}, $kid->{Round}, $kid->{Fill}, $kid->{Centered} );
		} else {
			$this->drawRect( $kid->{Width}, $kid->{Height}, $kid->{Fill}, $kid->{Centered} );
		}
	} elsif( $cmd eq 'DrawPolygon' ){
		for( qw(Rotation Tilt Fill) ){ $kid->{$_} ||= 0; }
		$this->drawPolygon( $kid->{Radius}, $kid->{Sides}, $kid->{Rotation}, $kid->{Tilt}, $kid->{Fill} );
	} elsif( $cmd eq 'DrawCircle' ){
		$this->drawCircle( $kid->{Radius}, ( $kid->{Fill} || 0 ) );
	} elsif( $cmd eq 'DrawEllipse' ){
		for( qw(Rotation Fill) ){ $kid->{$_} ||= 0; }
		$this->drawEllipse( $kid->{A}, $kid->{B}, $kid->{Rotation}, $kid->{Fill} );
	} elsif( $cmd eq 'DrawArc' ){
		if( defined $kid->{A} && defined $kid->{B} ){
			$this->drawOvalArc( $kid->{A}, $kid->{B}, $kid->{From}, $kid->{To}, ( $kid->{Fill} || 0 ) );
		} else {
			$this->drawArc( $kid->{Radius}, $kid->{From}, $kid->{To}, ( $kid->{Fill} || 0 ) );
		}
	} elsif( $cmd eq 'DrawGrid' || $cmd eq 'Table' ){
		for my $at ( 'Widths', 'Heights' ){
			next unless( defined $kid->{$at} );
			my @arr = split( /,\s*/, $kid->{$at} );
			$kid->{$at} = [ @arr ];
		}
		$this->drawGrid( $kid->{Width}, $kid->{Height}, ( $kid->{Fill} || 0 ), $kid );
	} elsif( $cmd eq 'ShowImage' ){
		$this->showImage( &PDF::getObjByName( $kid->{Name} ), $kid->{Left}, $kid->{Bottom}, $kid );
	} elsif( $cmd eq 'ShowXObject' ){
		$this->showXObject( &PDF::getObjByName( $kid->{Name} ), $kid->{Left}, $kid->{Bottom}, $kid );
	} elsif( $cmd eq 'ShowWMF' ){
		$this->showWMF( $kid->{File}, $kid->{Left}, $kid->{Top}, $kid );
	} elsif( $cmd eq 'ShowText' || $cmd eq 'ShowBanner' ){
		$kid->{Text} =~ s/\xC2([\x80-\xBF])/$1/g;
		$kid->{Text} =~ s/\xC3([\x80-\xBF])/chr( ord( $1 ) + 64 )/ge;
		if( defined $kid->{Shading} ){
			$kid->{Shading} = &PDF::getObjByName( $kid->{Shading} );
		} elsif( defined $kid->{Texture} ){
			$kid->{Texture} = &PDF::getObjByName( $kid->{Texture} );
		}
		if( $cmd eq 'ShowText' ){
			$this->showText( $kid->{X}, $kid->{Y}, $kid->{Text}, $kid );
		} else {
			$this->showBanner( $kid->{X}, $kid->{Y}, $kid->{Text}, $kid->{Radius}, $kid );
		}
	} elsif( $cmd eq 'DrawCustom' ){
		if( $kid->{Type} eq 'Postnet' ){
			$this->drawPostnet( $kid->{X}, $kid->{Y}, $kid->{Zip}, ( $kid->{Dest} || undef ) );
		} elsif( $kid->{Type} eq 'FIM' ){
			$this->drawFIM( $kid->{X}, $kid->{Y}, $kid->{FIMType} );
		}
	}
	pop( @{$this->{CallStack}} );
}

sub newFromXML {
	my( $class, $xml ) = @_;
	my $this;
	bless $xml, 'HASH';
	if( defined $xml->{Rect} ){
		my @rectsides = split( /,\s*/, $xml->{Rect} );
		$this = new GraphContent( new Rect( @rectsides ), $xml );
	} else {
		$this = new GraphContent( $xml );
	}
	foreach ( @{$xml->{Kids}} ){
		$this->execXML( $_ );
	}
	@{$xml->{Kids}} = ( );
	return $this;
}

sub customCode {
	my $this = shift;
	if( $this->{Tagged} ){
		print "$PDF::endln/LayerCreator /PDFEverywhere ";
		print sprintf( '%s/LayerID <%s> ', $PDF::endln, unpack( 'H*', ( $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{LayerId} ): $this->{LayerId} ) ) );
		print sprintf( '%s/LayerXML %d 0 R ', $PDF::endln, $this->{TagXMLObject}->{ObjId} );
	}
}

sub makeCode {
	my $this = shift;
	my $OrigData = $this->{Stream};
	if( $this->{Tagged} ){
		$this->{LayerId} = PDF::MD5( $OrigData );
		if( exists $PDF::root->{LayerIds}->{ $this->{LayerId} } ){
			$this->{TagXMLObject} = $PDF::root->{LayerIds}->{ $this->{LayerId} };
		} else {
			my $xmlstart = tell;
			$this->startXML( 0 );
			$this->endXML( 0 );
			my $xmlend = tell;
			my $xml;
			seek( select, $xmlstart, 0 );
			read( select, $xml, $xmlend - $xmlstart );
			truncate( select, $xmlstart );
			seek( select, 0, 2 );
			$this->{TagXMLObject} = new PDFStream( $xml );
			$this->appendChild( $this->{TagXMLObject} );
			$this->{TagXMLObject}->{ObjId} = ++$PDF::root->{ObjectID};
			$PDF::root->{LayerIds}->{ $this->{LayerId} } = $this->{TagXMLObject};
		}
	}
	$this->{Stream} = join( ' ', ' q ', $this->{Stream}, ' Q ' );
	$this->{DataChanged} = 1;
	$this->SUPER::makeCode( );
	$this->{Stream} = $OrigData;
	$this->{CodeCreated} = 1;	# XObject will need this to determine whether or not to add the 'q' and 'Q'
}

sub cleanUp {
	my $this = shift;
	delete $this->{TagXMLObject};
}

sub finalize {
	my $this = shift;
	$this->SUPER::finalize( );
	undef $this->{Resources};
}

sub getBookmark {
	return $PDF::root->getObjByName( shift->{BookmarkName} );
}

1;
