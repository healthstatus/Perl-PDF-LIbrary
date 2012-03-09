#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package FloatingText;

@ISA = qw(TextContent);

sub new {
	my( $class, $parm, $text, $attr ) = @_;
	my $this;
	if( ref( $parm ) eq $class ){
		$this = new TextContent( bless( $parm, 'TextContent' ), $attr );
		bless $parm, $class;
		$text = $parm->{Text};
	} else {
		$this = new TextContent( $parm, $attr );
	}
	bless $this, $class;
	$this->{Voracious} = 1;
	if( ref( $text ) eq 'SCALAR' ){
		$$text .= ' ^C';
	} else {
		$text .= ' ^C';
	}
	my @myparas = ( );
	$this->reformatText( ( ref( $text ) eq 'SCALAR'? $text: \$text ), \@myparas );
	unshift( @TextContent::Paragraphs, @myparas );
	my @save = ( $TextContent::ContinuedPara, $TextContent::InStyle );
	$TextContent::ContinuedPara = 0;
	$TextContent::InStyle = 0;
	$this->TextContent::importText( );
	( $TextContent::ContinuedPara, $TextContent::InStyle ) = @save;
	return $this;
}

# A mere interface for backward compatibility.
sub importText {
	my $this = shift;
}

# Note: TextContent has no "newFromXML" method, while FloatingText has no "startXML" and "endXML" methods.

sub newFromXML {
	my( $class, $xml ) = @_;
	my $container;
	if( exists $xml->{Rect} ){
		$container = new Rect( split( /,\s*/, $xml->{Rect} ) );
	} elsif( exists $xml->{Poly} ){
		$container = new Poly( split( /,\s*/, $xml->{Poly} ) );
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
	return new FloatingText( $container, $text, $xml );
}

1;
