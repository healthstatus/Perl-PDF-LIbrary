#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#
# Abstract class. No direct instantiation.

package PDFTreeNode;

# Object privileges, determining the sequence of children.
%PDFTreeNode::Privileged = (
	DocInfo => 5,		# Document level: highest priority
	Catalog => 5,
	ImageContent => 4,	# Resources, must be defined first
	PDFTexture => 4,
	PDFShading => 4,
	PDFFont => 4,
	EmbeddedFont => 4,
	XObject => 3,		# Still a resource, but may use other resources
	NamesTree => 2,
	Page => 2,
	PureXMLNode	=> 2,	# Only as child of Pages to represent an XML node
	GraphContent => 1,	# Contents must be defined before form
	TextContent => 1,
	FloatingText => 1,
	PreformText => 1,
	AcroForm => 0,
	Outlines => -1,		# Outlines are defined at last
);

for( qw(Annot Appearance ColorSpace EmbeddedFile ExtGState Field
	FontDescriptor Pages PDFDocEncoding PDFStream PDFEncrypt) ){
	$PDFTreeNode::Privileged{$_} = 0;
}

# Common methods for all modules
sub encrypt { }
sub makeCode { }
sub cleanUp { }
sub startXML { }
sub endXML { }
sub newFromXML { }
sub firstChild { shift->{'son'} }
sub lastChild { shift->{'last'} }
sub prevSibling { shift->{'prev'} }
sub nextSibling { shift->{'next'} }

# Return value: an array of childern nodes (references to objects).
sub children {
	my $this = shift;
	my @kids = ( );
	if( ref( $this ) && defined $this->{son} ){
		my $ptr = $this->{son};
		do { push @kids, $ptr; $ptr = $ptr->{next}; } until( !$ptr );
	}
	return @kids;
}

# Add another PDFTreeNode as its child
sub appendChild {
	my ( $this, $child ) = @_;
	my $priv = ( defined $PDFTreeNode::Privileged{ ref( $child ) }?
		$PDFTreeNode::Privileged{ ref( $child ) }: 0 );
	my $ptr = $this->{son};
	while( $ptr && $PDFTreeNode::Privileged{ ref( $ptr ) } >= $priv ){
		$ptr = $ptr->{next};
	}
	if( $ptr ){
		$child->{next} = $ptr;
		$child->{prev} = $ptr->{prev};
		if( $ptr->{prev} ){
			$ptr->{prev}->{next} = $child;
		} else {
			$this->{son} = $child;
		}
		$ptr->{prev} = $child;
	} else {
		if( $this->{son} ){
			$this->{last}->{next} = $child;
			$child->{prev} = $this->{last};
		} else {
			$this->{son} = $child;
		}
		$this->{last} = $child;
	}
	$child->{par} = $this;
	return $child;
}

# Add another PDFTreeNode as its sibling (next)
sub appendSibling {
	my ( $this, $sib ) = @_;
	if( $this->{next} ){
		$sib->{next} = $this->{next};
		$this->{next}->{prev} = $sib;
	}
	$sib->{prev} = $this;
	$this->{next} = $sib;
	if( $this->{par}->{last} == $this ){
		$this->{par}->{last} = $sib;
	}
	$sib->{par} = $this->{par};
	return $sib;
}

# Add another PDFTreeNode as its sibling (previous)
sub prependSibling {
	my ( $this, $sib ) = @_;
	if( $this->{prev} ){
		$sib->{prev} = $this->{prev};
		$this->{prev}->{next} = $sib;
	}
	$sib->{next} = $this;
	$this->{prev} = $sib;
	if( $this->{par}->{son} == $this ){
		$this->{par}->{son} = $sib;
	}
	$sib->{par} = $this->{par};
	return $sib;
}

# Remove a PDFTreeNode from its children
sub deleteChild {
	my( $this, $child ) = @_;
	return if( $child->{par} != $this );
	if( $child->{next} ){
		$child->{next}->{prev} = $child->{prev};
	} else {
		$this->{last} = $child->{prev};
	}
	if( $child->{prev} ){
		$child->{prev}->{next} = $child->{next};
	} else {
		$this->{son} = $child->{next};
	}
	$child->{next} = undef;
	$child->{prev} = undef;
	$child->{par} = undef;
	$child->{ObjId} = 0;	# Important!
	return $child;
}

# Set name of this object; asks for the PDFDoc to give its name
sub setName {
	my $this = shift;
	my $name = shift;
	return $PDF::root->setName( $this, $name );
}

# Return the corresponding properties
sub getName { shift->{Name} }
sub getObjId { shift->{ObjId} }

sub finalize { }

sub releaseNode {
	my $node = shift;
	$node->finalize( );
	if( $node->{son} ){
		my $p = $node->{son};
		while( $p ){
			my $q = $p->{next};
			releaseNode( $p );
			$p = $q;
		}
		delete $node->{son};
		delete $node->{last};
	}
	delete $node->{prev};
	delete $node->{next};
	delete $node->{par};
}


#===========================================================================#

package PureXMLNode;

@ISA = qw(PDFTreeNode);

sub new {
	my( $class, $tag, $attr ) = @_;	# $attr must be a hash ref!
	my $this = { Tag => $tag, Attr => $attr };
	bless $this, $class;
}

sub startXML {
	my( $this, $dep ) = @_;
	print "\t" x $dep, "<", $this->{Tag};
	for( keys %{$this->{Attr}} ){
		print qq{ $_="}, &PDF::escXMLChar( $this->{Attr}->{$_} ), '"';
	}
	print " />\n";
}

1;
