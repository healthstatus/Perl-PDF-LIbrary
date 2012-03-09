#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package PreformText;

use Text::Tabs;
use Text::Wrap;

@ISA = qw(TextContent);

$PreformText::endln = "\x0D\x0A";

sub new {
	my( $class, $parm, $text, $attr ) = @_;
	$attr->{FontFace} = "Courier";
	my $this;
	if( ref( $parm ) eq $class ){
		$this = new TextContent( bless( $parm, 'TextContent' ), $attr );
		bless $parm, $class;
		for( qw(Text AutoWrap Columns TapStop) ){
			$this->{$_} = $parm->{$_};
		}
	} else {
		$this = new TextContent( $parm, $attr );
		$this->{Text} = $text;
		$this->{TabStop} = ( $attr->{TabStop} || 4 );
		if( $attr->{Columns} ){
			$this->{Columns} = $attr->{Columns};
			$this->{AutoWrap} = 1;
		} elsif( $attr->{AutoWrap} ){
			$this->{AutoWrap} = 1;
		}
	}
	bless $this, $class;
	if( $this->{ContentPadding} ){
		$this->{Container}->shrink( &PDF::tellSize( $this->{ContentPadding} ) );
	}
	$this->setPos( );
	$this->setLeading( );
	$this->setColor( );
	$this->setFont( );
	$Text::Tabs::tabstop = $this->{TabStop};
	my @lines = map{ expand( $_ ); } split( /\n/, $this->{Text} );
	if( $this->{AutoWrap} ){
		if( $this->{Columns} ){
			$Text::Wrap::columns = $this->{Columns};
		} else {
			$Text::Wrap::columns = int( ( $this->{Container}->width( ) - &PDF::tellSize( $this->{ContentPadding} )
			- &PDF::tellSize( $this->{PaddingLeft} ) - &PDF::tellSize( $this->{PaddingRight} ) ) / $this->{Size} / 0.6 );
		}
		@lines = map{
			/^$/? $_: split( /\n/, wrap( '', '', $_ ) );
		} @lines;
	}
	$this->newLine( );
	for( @lines ){
		$this->moveBy( &PDF::tellSize( $this->{PaddingLeft} ), 0 ) if( defined $this->{PaddingLeft} );
		$this->addText( $_ );
		$this->newLine( );
	}
	$this->verticalAlign( );
	if( $this->{ContentPadding} ){
		$this->{Container}->shrink( &PDF::tellSize( $this->{ContentPadding} ) * (-1) );
	}
	$this->{Stream} .= "${PreformText::endln}ET ${PreformText::endln}";
	return $this;
}

sub importText {
	my $this = shift;	# To overwrite parent class's same method.
}

sub startXML {
	my( $this, $dep ) = @_;
	return if( $this->{IsCopy} );
	print "\t" x $dep, '<Text Preform="1" Rect="',
		join( ', ', $this->{Container}->left( ), $this->{Container}->bottom( ),
			$this->{Container}->right( ), $this->{Container}->top( ) ), '"';
	for( qw(Name TabStop Columns AutoWrap ContentPadding PaddingLeft PaddingRight FontSize Leading
		Color BgColor BorderColor BorderWidth BorderDash VerticalAlign) ){
		next unless( defined $this->{$_} );
		print qq{ $_="$this->{$_}"};
	}
	print q{ IsTemplate="1"} if( $this->{IsTemplate} );
	$this->{Text} =~ s/(\^[Cp]|\s)+$//;		# Remove redundant column-change signs.
	$this->{Text} =~ s/]]>/]] >/g;			# Text will be shown in CDATA segments.
	$this->{Text} =~ s{([\x80-\xFF]+)}{']]>' . join( '', map { join( '', '&#x', uc( unpack( 'H*', $_ ) ), ';' ) } split( //, $1 ) ) . '<![CDATA[' }ge;
	print '><![CDATA[', $this->{Text}, "]]>\n";
}

sub endXML {
	my( $this, $dep ) = @_;
	print "</Text>\n";
}

sub newFromXML {
	my( $class, $xml ) = @_;
	my $container;
	if( exists $xml->{Rect} ){
		$container = new Rect( split( /,\s*/, $xml->{Rect} ) );
	} elsif( exists $xml->{Row} && exists $xml->{Col} ){
		$container = $PDF::root->getCell( $xml->{Row}, $xml->{Col} );
		$container = $container->anchorRect(
			( exists $xml->{Width}? $xml->{Width}: undef ),
			( exists $xml->{Height}? $xml->{Height}: undef ),
			( exists $xml->{Anchor}? $xml->{Anchor}: undef ),
			new Rect( $container ),
		);
	}
	my $text = '';
	foreach my $kid ( @{$xml->{Kids}} ){
		next unless( ref( $kid ) =~ /::Characters$/ );
		$text .= $kid->{Text};
	}
	$text =~ s/\xC2([\x80-\xBF])/$1/g;
	$text =~ s/\xC3([\x80-\xBF])/chr( ord( $1 ) + 64 )/ge;
	@{$xml->{Kids}} = ( );
	bless $xml, 'HASH';
	return new PreformText( $container, $text, $xml );
}

1;
