#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package PDFStream;

use PDFTreeNode;
use Compress::Zlib;
use IO::Seekable;
use FileHandle;

@ISA = qw(PDFTreeNode);

sub new {
	my( $class, $data, $attr ) = @_;
	my $this = {
		'Filters' => [ ],
		'DecodeParms' => [ ],
		'Stream' => '',
		'FileHandle' => undef,
		'StreamStart' => 0,
		'StreamLength' => 0,
		'DiskBased' => 0,
	};
	bless $this, $class;
	if( defined $attr->{DecodeParms} && ref( $attr->{DecodeParms} ) eq 'ARRAY' ){
		push( @{$this->{DecodeParms}}, @{$attr->{DecodeParms}} );
	}
	if( defined $attr->{Filters} && ref( $attr->{Filters} ) eq 'ARRAY' ){
		push( @{$this->{Filters}}, @{$attr->{Filters}} );
	}
	$this->{Stream} = $data;
	return $this;
}

sub setDiskBased {
	my $this = shift;
	return if( $this->{DiskBased} || !defined $this->{FileHandle} );
	$this->{DiskBased} = 1;
	seek( $this->{FileHandle}, 0, SEEK_END );
	$this->{StreamStart} = tell( $this->{FileHandle} );
	$this->{FileHandle}->print( $this->{Stream} );
	$this->{StreamLength} = length( $this->{Stream} );
	$this->{Stream} = '';
}

# This method is abstract and may be defined in subclasses to generate PDF
# code specific to that class. The implementation must only writes dictionary
# key/value pairs, started with a line break.
sub customCode { }

sub setFilter {
	my( $this, $filter, $decodeparm ) = @_;
	unshift( @{$this->{Filters}}, $filter );
	unshift( @{$this->{DecodeParms}}, ( $decodeparm || 'null' ) );
}

sub makeCode {
	my $this = shift;
	print qq{$this->{ObjId} 0 obj$PDF::endln<<};
	$this->{DataChanged} = 0;
	$this->customCode( );
	my @filters = @{$this->{Filters}};
	my @decodeparms = @{$this->{DecodeParms}};
	my $OrigData = '';
	my( $OrigOffset, $OrigLength ) = ( 0, 0 );	# Disk-based option
	if( $PDF::root->{Prefs}->{UseCompress} ){
		if( !$this->{DataChanged} ){
			if( $this->{DiskBased} ){
				$OrigOffset = $this->{StreamStart};
				$OrigLength = $this->{StreamLength};
			} else {
				$OrigData = $this->{Stream};
			}
			$this->{DataChanged} = 1;
		}
		if( $this->{DiskBased} ){
			my $data;
			seek( $this->{FileHandle}, $this->{StreamStart}, SEEK_SET );
			read( $this->{FileHandle}, $data, $this->{StreamLength} );
			$data = Compress::Zlib::compress( $data );
			seek( $this->{FileHandle}, 0, SEEK_END );
			$this->{StreamStart} = tell( $this->{FileHandle} );
			$this->{FileHandle}->print( $data );
			$this->{StreamLength} = length( $data );
		} else {
			$this->{Stream} = Compress::Zlib::compress( $this->{Stream} );
		}
		$this->setFilter( 'FlateDecode' );
	}
	if( $PDF::root->{Encrypt} ){
		if( !$this->{DataChanged} ){
			if( $this->{DiskBased} ){
				$OrigOffset = $this->{StreamStart};
				$OrigLength = $this->{StreamLength};
			} else {
				$OrigData = $this->{Stream};
			}
			$this->{DataChanged} = 1;
		}
		if( $this->{DiskBased} ){
			my $data;
			seek( $this->{FileHandle}, $this->{StreamStart}, SEEK_SET );
			read( $this->{FileHandle}, $data, $this->{StreamLength} );
			$data = &PDF::RC4( $this->{EncKey}, $data );
			seek( $this->{FileHandle}, 0, SEEK_END );
			$this->{StreamStart} = tell( $this->{FileHandle} );	# Length is the same
			$this->{FileHandle}->print( $data );
		} else {
			$this->{Stream} = &PDF::RC4( $this->{EncKey}, $this->{Stream} );
		}
	} elsif( $PDF::root->{Prefs}->{UseASCII85} ){
		if( !$this->{DataChanged} ){
			if( $this->{DiskBased} ){
				$OrigOffset = $this->{StreamStart};
				$OrigLength = $this->{StreamLength};
			} else {
				$OrigData = $this->{Stream};
			}
			$this->{DataChanged} = 1;
		}
		if( $this->{DiskBased} ){
			my $data;
			seek( $this->{FileHandle}, $this->{StreamStart}, SEEK_SET );
			read( $this->{FileHandle}, $data, $this->{StreamLength} );
			&PDF::encodeA85( \$data );
			seek( $this->{FileHandle}, 0, SEEK_END );
			$this->{StreamStart} = tell( $this->{FileHandle} );
			$this->{FileHandle}->print( $data );
			$this->{StreamLength} = length( $data );
		} else {
			&PDF::encodeA85( \($this->{Stream}) );
		}
		$this->setFilter( 'ASCII85Decode' );
	}
	if( @{$this->{Filters}} ){
		print join( $PDF::endln, '', '/Filter [ /' . join( ' /', @{$this->{Filters}} ) . ' ] ' );
	}
	if( @{$this->{DecodeParms}} ){
		print join( $PDF::endln, '', '/DecodeParms [ ' . join( ' ', @{$this->{DecodeParms}} ) . ' ] ' );
	}
	print join( $PDF::endln,
		'',
		sprintf( '/Length %d', $this->{DiskBased}? $this->{StreamLength}: length( $this->{Stream} ) ),
		'>>',
		'stream',
		'',
	);
	if( $this->{DiskBased} ){
		my $data;
		seek( $this->{FileHandle}, $this->{StreamStart}, SEEK_SET );
		read( $this->{FileHandle}, $data, $this->{StreamLength} );
		print $data;
	} else {
		print $this->{Stream};
	}
	print join( $PDF::endln,
		'',
		'endstream',
		'endobj',
		''
	);
	if( $this->{DataChanged} ){
		if( $this->{DiskBased} ){
			seek( $this->{FileHandle}, $OrigStart, SEEK_SET );
			read( $this->{FileHandle}, $data, $OrigLength );
			seek( $this->{FileHandle}, 0, SEEK_END );
			$this->{StreamStart} = tell( $this->{FileHandle} );
			$this->{FileHandle}->print( $data );
		} else {
			$this->{Stream} = $OrigData;
		}
		@{$this->{Filters}} = @filters;
		@{$this->{DecodeParms}} = @decodeparms;
	}
}

sub DESTROY {
	my $this = shift;
	undef $this->{FileHandle};
	undef $this->{Stream};
}

1;
