#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#
# Packages in this file (only PDFFile is directly substantiable):
# PDF		Defines certain additional functions for manipulating PDF data
# PObject   Represents a PDF object in a PDF file
# PDFFile   Represents a PDF file; can be instantiated
#
# Dependency:
#	Relys on variables and subroutines defined in "shared.pl".
#
# Other inner classes for PDF data types:
# PDict		Dictionary
# PName		Name
# PNumber	Number
# PHexStr	Hex string
# PCharStr	Character string
# PArray	Array
# PRef		Reference (indirect object)
#
# Specifications:
# <<recursive>>
#	parsePDF( chunk: StringRef )
#	printPDF( data: PDFDataType )
#	encryptPDF( data: PDFDataType, ekey: String )
#	copyPDF( pobj: PObject, data: PDFDataType, referred: HashRef )
# <<special>>
#	PDict::type( ): String
# <<PObject>>
#	PObject::new( file: PDFFile, start: int, end: int, id: int ): PObject
#	PObject::readIt( ): PObject
#	PObject::parseIt( ): PObject
#	PObject::printIt( ): PObject
#	PObject::copyIt( refered: HashRef ): PObject
#	PObject::encryptIt( key: string ): PObject
# <<PDFFile>>
#	PDFFile::new( filename: String ): PDFFile
#	PDFFile::getObjectData( start: int, end: int ): String
#	PDFFile::getObjectById( ObjId: int, GenId: int ): PObject
#	PDFFile::getObjectByRef( ref: PRef ): PObject
#	PDFFile::printFile( outfile: String )
#	PDFFile::analyzePages( ): int {page count}
#	PDFFile::getEncryptState( ): boolean {true = encrypted}
#	PDFFile::getDocInfo( ): PObject
#	PDFFile::getCatalog( ): PObject
#	PDFFile::getAcroForm( ): PObject
#	PDFFile::getPages( refered: HashRef, numbers[]: int ): ArrayRef[2]
#	PDFFile::encrypt( setting: HashRef )
#	PDFFile::decrypt( OwnerPwd: String, verbose: boolean )

package PDF;

use PDFUtil;
use bytes;

$PDF::ChunkOffset = 0;
$PDF::ChunkLength = 0;
$PDF::ChunkStream = 0;

%PDF::FileMap = ( );	# Key: file name (absolute); value: PDFFile object

# Requires a reference to a chunk of original PDF object data as-is.
# Returns the parsed data that is a blessed hash.
sub parsePDF {
	my $Chunk = shift;	# Remember it is a reference!
	if( $$Chunk =~ s/^<<\s*//s ){			# Dictionary
		$PDF::ChunkOffset += length( $& );
		my $this = { };		# Hash ref
		while( 1 ){
			if( $$Chunk =~ s/^>>\s*//s ){
				$PDF::ChunkOffset += length( $& );
				last;
			}
			$$Chunk =~ s/^\/([^\s<>\[\]\(\)\{\}\/%]+)\s*//s;
			$PDF::ChunkOffset += length( $& );
			my $ThisKey = $1;	# Has to be saved because of the following call.
			$this->{$ThisKey} = PDF::parsePDF( $Chunk );
		}
		if( $$Chunk =~ s/^stream\x0D?\x0A?//s ){	# Must be CRLF or LF, not CR alone
			$PDF::ChunkOffset += length( $& );
			$$Chunk =~ s/\x0D?\x0A?endstream\s*$//s;
			$PDF::ChunkStream = 1;
			$PDF::ChunkLength = length( $$Chunk );
			if( $PDF::ChunkLength < 4096 ){
				$this->{Stream} = $$Chunk;
			}
		}
		return bless $this, 'PDict';
	} elsif( $$Chunk =~ s/^<\s*//s ){		# Hex string
		$PDF::ChunkOffset += length( $& );
		$$Chunk =~ s/^([^>]*)>\s*//s;
		$PDF::ChunkOffset += length( $& );
		return bless [ $1 ], 'PHexStr';
	} elsif( $$Chunk =~ s/^\[\s*//s ){		# Array
		$PDF::ChunkOffset += length( $& );
		my $this = [ ];
		while( 1 ){
			if( $$Chunk =~ s/^\]\s*//s ){
				$PDF::ChunkOffset += length( $& );
				last;
			}
			push( @$this, PDF::parsePDF( $Chunk ) );
		}
		return bless $this, 'PArray';
	} elsif( $$Chunk =~ s/^(\d+)\s+(\d+)\s+R\s*//s ){	# Indirect object
		$PDF::ChunkOffset += length( $& );
		return bless { 'ObjId' => $1, 'GenId' => $2 }, 'PRef';
	} elsif( $$Chunk =~ s/^([\d\.\-\+]+)\s*//s ){		# Number
		$PDF::ChunkOffset += length( $& );
		return bless [ $1 ], 'PNumber';
	} elsif( $$Chunk =~ m/^\(/ ){	# Char string
		# Rewrote 02/15/2002 to parse all possible cases, the old RE can't do this.
		my $i = 0;
		my $j = 0;
		my $lev = 0;
		my $out = '';
		while( 1 ){
			my $s = substr( $$Chunk, $i, 1 );
			if( $s eq '\\' ){
				my $t = substr( $$Chunk, ++$i, 1 );
				if( $t =~ /[nrtbf\(\)\\]/ ){
					$out .= $UnescapeChars{$t};
				} elsif( $t =~ /[\x0D\x0A]/ ){
					if( $t eq "\x0D" && substr( $$Chunk, $i + 1, 1 ) eq "\x0A" ){
						$i++;
					}
				} elsif( $t =~ /\d/ ){
					for( 1..2 ){
						my $d = substr( $$Chunk, ++$i, 1 );
						if( $d =~ /\d/ ){
							$t .= $d;
						} else {
							$i--;
							last;
						}
					}
					$out .= chr( oct( $t ) );
				} else {
					$out .= $t;
				}
			} else {
				$s eq '(' && ++$lev ||
				$s eq ')' && --$lev;
				$out .= $s;
			}
			$i++;
			last if( !$lev );
		}
		substr( $$Chunk, 0, $i, '' );
		$$Chunk =~ s/^\s+//;
		$out =~ s/^\(//;
		$out =~ s/\)$//;
		return bless [ $out ], 'PCharStr';
	} elsif( $$Chunk =~ s/^%[^\x0D\x0A]*[\x0D\x0A]+//s ){	# Comment. Fixed 02/13/2003. Old code: s/^%[\x0D\x0A]+//s
		$PDF::ChunkOffset += length( $& );
		return PDF::parsePDF( $Chunk );
	} elsif( $$Chunk =~ s/^\/?([^\s<>\[\]\(\)\{\}\/%]*)\s*//s ){	# Name (fixed 07/17/02: + changed to * since "/" is a valid name)
		$PDF::ChunkOffset += length( $& );
		return bless [ $1 ], 'PName';
	} else {
		return bless [ 0 ], 'PNumber';	# For the rare case when the data is empty.
	}
}

# Print the parsed data into PDF output.
sub printPDF {
	my $data = shift;
	return unless( defined $data );
	if( ref( $data ) eq 'PDict' ){
		print "<< ";
		foreach my $key ( keys %$data ){
			next if( $key eq 'Stream' );
			print "/$key ";
			PDF::printPDF( $data->{$key} );
			print $PDF::endln;
		}
		print ">>";
		return unless( exists $data->{Stream} );
		print join( $PDF::endln, '', 'stream', $data->{Stream}, 'endstream ', );
	} elsif( ref( $data ) eq 'PName' ){
		print $data->[0] =~ /^null|false|true$/? "$data->[0] ": "/$data->[0] ";
	} elsif( ref( $data ) eq 'PNumber' ){
		print "$data->[0] ";
	} elsif( ref( $data ) eq 'PHexStr' ){
		print "<$data->[0]> ";
	} elsif( ref( $data ) eq 'PCharStr' ){
		print "(", PDF::escStr( $data->[0] ), ") ";
	} elsif( ref( $data ) eq 'PArray' ){
		print "[ ";
		for( @$data ){
			PDF::printPDF( $_ );
		}
		print "] ";
	} else {
		# $data is eith a PRef, a PObject, or a PDFTreeNode
		print "$data->{ObjId} $data->{GenId} R ";
	}
}

# Print the parsed data into PDF output.
sub encryptPDF {
	my $data = shift;
	my $ekey = shift;
	return unless( defined $data );
	if( ref( $data ) eq 'PDict' ){
		foreach my $key ( keys %$data ){
			next if( $key eq 'Stream' );
			PDF::encryptPDF( $data->{$key}, $ekey );
		}
		return unless( exists $data->{Stream} );
		$data->{Stream} = PDF::RC4( $ekey, $data->{Stream} );
	} elsif( ref( $data ) eq 'PHexStr' ){
		$data->[0] = PDF::strToHex( PDF::RC4( $ekey, PDF::hexToStr( $data->[0] ) ) );
		$data->[0] =~ s/^<|>$//g;
	} elsif( ref( $data ) eq 'PCharStr' ){
		$data->[0] = PDF::RC4( $ekey, $data->[0] );
	} elsif( ref( $data ) eq 'PArray' ){
		for( @$data ){
			PDF::encryptPDF( $_, $ekey );
		}
	}
}

# Value types that can be directly copied.
%PDF::DirectValueTypes = map { $_ => 1 } qw(PName PNumber PHexStr PCharStr);

# Dictionary keys that must be skipped during copying. Note this is a reference!
$PDF::SkippedValues = {
	Page		=> { Parent => 1, B => 1, StructParents => 1, ID => 1 },
	Annot		=> { P => 1, Dest => 1, A => 1, AA => 1, D => 1, B => 1, StructParent => 1 }, # Remove Dest and A to import all annotations
	Outlines	=> { SE => 1 },
};

# Duplicate a PDF data structure.
sub copyPDF {
	my( $pobj, $data, $referred ) = @_;
	if( defined $PDF::DirectValueTypes{ ref($data) } ){
		return bless [ $data->[0] ], ref( $data );
	} elsif( ref( $data ) eq 'PDict' ){
		my $newdata = { };
		my $type = $data->type( );
		foreach my $key ( keys %$data ){
			next if( $key eq 'Stream' );
			next if( defined $PDF::SkippedValues->{$type}->{$key} );
			$newdata->{$key} = PDF::copyPDF( $pobj, $data->{$key}, $referred );
		}
		if( exists $data->{Stream} ){
			$newdata->{Stream} = $data->{Stream};
			my $strlen = length( $data->{Stream} ) + length( $PDF::endln );	# Fixed: 08/07/2002; eol char should be counted, too
			# At this stage, the Length field, if previously PRef, has now been a PObject
			if( ref( $newdata->{Length} ) eq 'PObject' ){
				$newdata->{Length}->{Data}->[0] = $strlen;
			} else {
				$newdata->{Length}->[0] = $strlen;
			}
		}
		return bless $newdata, ref( $data );
	} elsif( ref( $data ) eq 'PArray' ){
		my $newdata = [ ];
		for my $elem ( @$data ){
			push( @$newdata, PDF::copyPDF( $pobj, $elem, $referred ) );
		}
		return bless $newdata, ref( $data );
	} elsif( ref( $data ) eq 'PRef' ){
		my $tmp = PDF::getPDFFile( $pobj->{FileName} )->getObjectByRef( $data );
		if( !defined $tmp ){
			return bless [ 'null' ], 'PName';
		}
		if( !defined $referred->{$tmp} ){
			$tmp->parseIt( );
			$tmp->copyIt( $referred );
		}
		return $referred->{$tmp};
	} elsif( ref( $data ) eq 'PObject' ){
		return $data;
	}
}

sub finalizePDF {
	my $data = shift;
	return if( !ref( $data ) || ref( $data ) eq 'PObject' );
	if( ref( $data ) eq 'PDict' ){
		delete $data->{Stream} if( exists $data->{Stream} );
		for ( values %$data ){ finalizePDF( $_  ); }
		%$data = ( );
	} elsif( ref( $data ) eq 'PArray' ){
		for ( @$data ){ finalizePDF( $_  ); }
		@$data = ( );
	} elsif( ref( $data ) eq 'PRef' ){
		%$data = ( );
	} elsif( $data->isa( 'ARRAY' ) ){
		@$data = ( );
	}
}

# Manage a dictionary that maps file name to PDF File objects

sub putPDFFile {
	my $pdffile = shift;
	removePDFFile( $pdffile );
	$PDF::FileMap{ $pdffile->{FileName} } = $pdffile;
}

sub removePDFFile {
	my $pdffile = shift;
	my $name = $pdffile->{FileName};
	if( exists $PDF::FileMap{$name} ){
		$PDF::FileMap{$name}->finalize( );
		delete $PDF::FileMap{$name};
	}
}

sub getPDFFile {
	my $name = shift;
	return $PDF::FileMap{$name} || undef;
}

#=============================================================================#

package PDict;

# This package is only used to determining if a referred object should be copied
# while extracting some objects, e.g. the Parent of a Page should be skipped.
sub type {
	my $this = shift;
	return exists $this->{Type}? $this->{Type}->[0]: ref( $this );
}

#=============================================================================#

package PCharStr;

sub getStr {
	return shift->[0];
}

sub setStr {
	my $this = shift;
	$this->[0] = shift;
}

#=============================================================================#

package PName;

sub getStr {
	return shift->[0];
}

#=============================================================================#

package PHexStr;

sub getStr {
	return PDF::hexToStr( shift->[0] );
}

sub setStr {
	my $this = shift;
	$this->[0] = unpack( 'H*', shift );
}

#=============================================================================#

package PObject;

use strict;
use Carp;
use IO::Seekable;
use FileHandle;
use bytes;

#$PObject::ObjId = 0;
@PObject::CopiedObjects = ( );
$PObject::TempFile = "PEV" . substr( unpack( 'H*', &PDF::MD5( time( ), rand( ) ) ), 0, 8 ) . ".TMP";
$PObject::FileHandle = new FileHandle;
$PObject::FileHandle->open( "+>$PDF::TempDir/$PObject::TempFile" ) or die "Can't open file $PObject::TempFile for output";
defined $PObject::FileHandle or confess "Can't open temporary file";
binmode( $PObject::FileHandle );
truncate( $PObject::FileHandle, 0 );

END {
	$PObject::FileHandle->close( );
	undef $PObject::FileHandle;
	unlink "$PDF::TempDir/$PObject::TempFile";
}

sub new {
	# $file		- PDFFile object
	# $start	- Offset of object data
	# $end		- End offset of object data
	# $id		- Object Id, optional
	my( $class, $file, $start, $end, $id ) = @_;
	my $this = {
		'FileName' => $file->{FileName},
		'FileHandle' => $file->{FileHandle},
		'Start' => $start,
		'End' => $end,
		'ObjId' => $id,
		'GenId' => 0,
		'Data' => undef,	# If defined, the original file has been read.
		'Parsed' => 0,		# If 1, the Data is parsed already.
		'Modified' => 0,	# If 1, the parsed content has been modified.
		'AddtionalOffset' => 0,
		'StreamStart' => 0,
		'StreamLength' => 0,
		'DiskBased' => 0,
	};
	bless $this, $class;
}

# Read the original object data in the PDF file and remove header and trailer
# but not parse it. Returns early if the original data are not well-defined.
# Also sets the object ID and generation ID.
sub readIt {
	my $this = shift;
	my $data = PDF::getPDFFile( $this->{FileName} )->getObjectData( $this->{Start}, $this->{End} );
	return $this unless( $data =~ s/^\s*(\d+)\s+(\d+)\s+obj\s*//s );	# Fixed 01/21/2002 to allow initial padding spaces
	$this->{AdditionalOffset} = length( $& );
	( $this->{ObjId}, $this->{GenId} ) = ( $1, $2 );
	$data =~ s/endobj\s*$//s;
	$this->{Data} = $data;
	$this->{Parsed} = 0;
	return $this;
}

# Parse the PDF data. Call readIt first if the data has not been read.
# The original data is discarded and the Data field now contains the parsed.
sub parseIt {
	my $this = shift;
	if( $this->{Parsed} ){
		return $this;
	}
	$this->readIt( ) unless( defined $this->{Data} );
	$PDF::ChunkOffset = 0;
	$PDF::ChunkStream = 0;
	# Robust fix 10/03/2002: If the data block doesn't exist, make it 'null'
	if( length( $this->{Data} ) == 0 ){
		$this->{Data} = bless [ 'null' ], 'PName';
		$this->{Parsed} = 1;
		return $this;
	}
	my $parsed = &PDF::parsePDF( \( $this->{Data} ) );
	$this->{Data} = $parsed;
	$this->{Parsed} = 1;
	if( $this->{Data}->isa( 'PDict' ) && $PDF::ChunkStream ){
		my $strlen;
		if( !exists $this->{Data}->{Stream} ){
			$this->{StreamStart} = $PDF::ChunkOffset;
			$this->{StreamLength} = $PDF::ChunkLength;
			$this->{DiskBased} = 1;
			$strlen = $this->{StreamLength};
		} else {
			$strlen = length( $this->{Data}->{Stream} );
		}
		$strlen += length( $PDF::endln );	# Fixed: 08/07/2002; eol char should be counted, too
		if( ref( $this->{Data}->{Length} ) eq 'PRef' ){
			if( exists $this->{Data}->{File} ){
				$this->{Data}->{File}->getObjectByRef( $this->{Data}->{Length} )->{Data}->[0] = $strlen;
			} else {
				$this->{Data}->{Length} = bless [ $strlen ], 'PNumber';
			}
		} elsif( ref( $this->{Data}->{Length} ) eq 'PObject' ){
			$this->{Data}->{Length}->parseIt( );
			$this->{Data}->{Length}->{Data}->[0] = $strlen;
		} else {
			$this->{Data}->{Length}->[0] = $strlen;
		}
	}
	return $this;
}

# Print the data. If the data is parsed
sub printIt {
	my $this = shift;
	if( $this->{Parsed} ){
		print "$this->{ObjId} $this->{GenId} obj$PDF::endln";
		eval {
			PDF::printPDF( $this->{Data} );
		}; if( $@ ){
			croak "Error printing object $this->{ObjId} $this->{GenId}: $@";
		}
		if( $this->{DiskBased} ){
			my $str = $this->getStreamData( );
			if( defined $str ){
				print $PDF::endln, 'stream', $PDF::endln;
				print $str;
				print $PDF::endln, 'endstream';
			}
		}
	} else {
		$this->readIt( ) unless( defined( $this->{Data} ) );
		print "$this->{ObjId} $this->{GenId} obj$PDF::endln";
		print $this->{Data};	# No need to parse it here.
	}
	print "${PDF::endln}endobj${PDF::endln}";
	return $this;
}

# Duplicate an existing PObject instance. All Ref instances will cause the
# corresponding PObject be read, parsed, duplicated, and linked to the new
# Ref so the returned value is essentially a tree of objects, and all those
# referred in the top-level PObject are guaranteed to be available. However, a
# list of new object ids must be assigned before they can be used elsewhere.
sub copyIt {
	my( $this, $referred ) = @_;
	$this->parseIt( );
	my $that = {
		'FileName' => $this->{FileName},
		'FileHandle' => $PObject::FileHandle,
		'Start' => 0,
		'End' => 0,
		'ObjId' => 0,
		'GenId' => 0,
		'Data' => undef,
		'Parsed' => 1,
		'Modified' => 0,
		'AddtionalOffset' => 0,
		'StreamStart' => 0,
		'StreamLength' => $this->{StreamLength},
		'DiskBased' => $this->{DiskBased},
	};
	bless $that, ref( $this );	# Could be a derived class type!
	# $referred associates an original object and its copy.
	# $referred is externally managed; it must be a hash reference.
	$referred->{ $this } = $that;
	$that->{Data} = PDF::copyPDF( $this, $this->{Data}, $referred );
	if( $this->{DiskBased} ){
		for( qw(FileHandle Start AdditionalOffset StreamStart StreamLength) ){
			$that->{$_} = $this->{$_};
		}
	}
	push( @PObject::CopiedObjects, $that );
	return $that;
}

# Encrypt the PObject data
sub encryptIt {
	my $this = shift;
	my( $key, $strong ) = @_;
	my $ekey = substr( PDF::MD5( $key, substr( pack( 'V', $this->{ObjId} ), 0, 3 ),
		substr( pack( 'V', $this->{GenId} ), 0, 2 ) ), 0, ( $strong? 16: 10 ) );
	PDF::encryptPDF( $this->{Data}, $ekey );
	if( $this->{DiskBased} ){
		my $str = $this->getStreamData( );
		seek( $PObject::FileHandle, 0, SEEK_END );
		$this->{FileHandle} = $PObject::FileHandle;
		$this->{AdditionalOffset} = 0;
		$this->{Start} = tell( $this->{FileHandle} );
		$this->{StreamStart} = 0;
		$this->{FileHandle}->print( PDF::RC4( $ekey, $str ) );
	}
	return $this;
}

sub getStreamData {
	my $this = shift;
	$this->parseIt( ) if( !$this->{Parsed} );
	return $this->{Data}->{Stream} unless( $this->{DiskBased} );
	seek( $this->{FileHandle}, $this->{Start} + $this->{StreamStart} + $this->{AdditionalOffset}, SEEK_SET );
	my $Buffer;
	read( $this->{FileHandle}, $Buffer, $this->{StreamLength} );
	return $Buffer;
}

sub getObjId { shift->{ObjId}; }

sub finalize {
	my $this = shift;
	delete $this->{FileHandle} if( exists $this->{FileHandle} );
	PDF::finalizePDF( $this->{Data} ) if( exists $this->{Data} );
	%$this = ( );
}

sub DESTROY {
	shift->finalize( );
}

#=============================================================================#

package PDFFile;

use strict;
use IO::Seekable;
use FileHandle;
use Carp;
use File::Basename;
use bytes;

sub new {
	my( $class, $filename ) = @_;
	# Try open the file and read the header
	my $fh = new FileHandle( );
	$fh->open( "<$filename" ) or croak "Can't open file $filename for input";
	my $this = {
		'FileName' => $filename,
		'FileHandle' => $fh,
		'Length' => 0,			# Original file length
		'Linearized' => 0,		# 1 or 0, boolean
		'Encrypted' => 0,		# 1 or 0, boolean
		'Revisions' => 0,		# Number of revisions, integer
		'Trailers' => [ ],		# Array of trailer as PDict
		'Boundaries' => [ ],	# Integers marking the boundaries between objects
		'XrefOffsets' => [ ],	# Offsets of Xref tables; a subset of the Boundaries array
		'Version' => '',		# PDF version
		'Objects' => [ ],		# PObject objects
		'ObjRefById' => { },	# Key: object Id; value: Array of subscripts to the Objects array
		'PagesAnalyzed' => 0,	# Flag value
		'PageRefs' => [ ],		# References to PObjects for the pages
		'PageOrders' => { },	# Reverse of PageRefs array (10/07/2002)
		'Names' => { },			# Key: name; value: PArray defining a destination
		'NamesAnalyzed' => 0,	# Flag value
	};
	bless $this, $class;
	PDF::putPDFFile( $this );

	binmode $this->{FileHandle};
	my %ObjIdByOffset = ( );

	my( $StartXref, $EndOfTrailer, $Buffer ) = ( 0 ) x 3;
	# $StartXref	- Integer, start of Xref chunk
	# $EndOfTrailer	- Integer, offset of end of current trailer

	# Now go to the end of file to find out the length of the file
	seek( $this->{FileHandle}, 0, SEEK_END );
	$this->{Length} = tell( $this->{FileHandle} );
	push( @{$this->{Boundaries}}, $this->{Length} );

	# PDF standard: the header is within the first 1024 bytes.
	seek( $this->{FileHandle}, 0, SEEK_SET );
	read( $this->{FileHandle}, $Buffer, 1024 );
	if( $Buffer =~ /%PDF-(\d\.\d)\b/s || $Buffer =~ /%!PS\.Adobe\.\d\.\d PDF\.(\d\.\d)\b/s ){
		$this->{Version} = $1;
	} else {
		croak "File $filename doesn't appear to be a valid PDF file";
	}

	# Pull out the first dictionary to see if it is linearized;
	# PDF standard requires the entire linearization dictionary to be contained in the first 1024 bytes.
	if( $Buffer =~ /<<(?:(?!(<<))(?!(>>)).)*>>/s ){
		my $TestData = $&;
		my $TestObj = PDF::parsePDF( \$TestData );
		# If the file indeed is linearized
		if( defined $TestObj->{Linearized} ){
			$this->{Linearized} = 1;
			# If the recorded length is shorter than actual, then the file must
			# have been updated; it equal, then the value should be saved.
			if( $TestObj->{L}->[0] < $this->{Length} ){
				$this->{Revisions} = 1;
			} elsif( $TestObj->{L}->[0] > $this->{Length} ){
				croak "File $filename seems corrupted because the length is shorter than expected";
			}
			# Read the original end trailer
			$EndOfTrailer = $TestObj->{L}->[0];
			$StartXref = $TestObj->{T}->[0];
			seek( $this->{FileHandle}, $StartXref, SEEK_SET );
			read( $this->{FileHandle}, $Buffer, $EndOfTrailer - $StartXref );
			# Get StartXref for the first xref table
			$Buffer =~ s/startxref[\x0D\x0A]+(\d+)[\x0D\x0A]+%%EOF//s;
			$StartXref = $1;
			unshift( @{$this->{Boundaries}}, $StartXref );
			push( @{$this->{XrefOffsets}}, $StartXref );
			# Get the trailer dictionary
			$Buffer =~ s/<<(?:(?!(<<))(?!(>>)).)*>>//s;
			my $TrailerData = $&;
			my $Trailer = PDF::parsePDF( \$TrailerData );
			# $TrailerData	- Trailer dictionary data (original)
			# $Trailer		- Current trailer object (parsed)
			unshift( @{$this->{Trailers}}, $Trailer );
			# We care about the ordering of the trailer array; last one first.

			# Now we read the Xref entries
			my $ObjId = 0;
			for( split( /\x0D\x0A| [\x0D\x0A]/, $Buffer ) ){
				if( /([\-\+\d]{10}) \d{5} ([fn])/ ){ # Fix: 10/01/2002. DocOut creates entries with negative values.
					unless ( $2 eq 'f' ){
						push( @{$this->{Boundaries}}, $1 + 0 );
						$ObjIdByOffset{ $1 + 0 } = $ObjId;
					}
					$ObjId++;
				} elsif( /trailer/ ){
					last;
				}
			}

			# Next, we go back to file head, get 1024 bytes from the startxref
			seek( $this->{FileHandle}, $StartXref, SEEK_SET );
			read( $this->{FileHandle}, $Buffer, 1024 );
			# However, we only read the first two entries in the Xref table,
			# just to find out the boundaries for the current xref section.
			my $FirstObjOffset = 0;
			$EndOfTrailer = 0;
			for( split( /\x0D\x0A| [\x0D\x0A]/, $Buffer ) ){
				if( /([\-\+\d]{10}) \d{5} n/ ){
					if( !$FirstObjOffset ){ $FirstObjOffset = $1 + 0; }
					else { $EndOfTrailer = $1 + 0; last; }
				}
			}

			# At this time, we read the precise range of data for the trailer
			seek( $this->{FileHandle}, $StartXref, SEEK_SET );
			read( $this->{FileHandle}, $Buffer, $EndOfTrailer - $StartXref );
			$Buffer =~ s/<<(?:(?!(<<))(?!(>>)).)*>>//s;
			$TrailerData = $&;
			$Trailer = PDF::parsePDF( \$TrailerData );
			unshift( @{$this->{Trailers}}, $Trailer );
			push( @{$this->{XrefOffsets}}, $Trailer->{Prev}->[0] );
			push( @{$this->{Boundaries}}, $Trailer->{Prev}->[0] );
			for( split( /\x0D\x0A| [\x0D\x0A]/, $Buffer ) ){
				if( /([\-\+\d]{10}) \d{5} n/ ){
					push( @{$this->{Boundaries}}, $1 + 0 );
					$ObjIdByOffset{ $1 + 0 } = $ObjId;
					$ObjId++;
				} elsif( /(\d+) \d+/ ){
					$ObjId = $1;
				} elsif( /trailer/ ){
					last;
				}
			}
		}
	}

	# For a linearized and not updated file, no more trailers is present.
	unless( $this->{Linearized} && !$this->{Revisions} ){
		# According to PDF standard, within last 1024 bytes there must be a trailer.
		seek( $this->{FileHandle}, -1024, SEEK_END );
		read( $this->{FileHandle}, $Buffer, 1024 );

		undef $StartXref;
		# If there is more than one "startxref" section, only get the last one.
		while( $Buffer =~ /startxref\x20*[\x0D\x0A]+\x20*(\d+)\x20*[\x0D\x0A]+\x20*%%EOF/gs ){
			$StartXref = $1;
		}
		unless( defined( $StartXref ) ){
			croak "Trailer missing in file $filename";
		}
		$EndOfTrailer = $this->{Length};

		# Now we read all the trailers and Xref tables.
		while( 1 ){
			push( @{$this->{Boundaries}}, $StartXref );
			push( @{$this->{XrefOffsets}}, $StartXref );
			my( $TrailerData, $Trailer ) = ( );
			seek( $this->{FileHandle}, $StartXref, SEEK_SET );
			read( $this->{FileHandle}, $Buffer, $EndOfTrailer - $StartXref );
			while( $Buffer =~ m/<<(?:(?!(<<))(?!(>>)).)*>>/gs ){
				$TrailerData = $&;
				$Trailer = PDF::parsePDF( \$TrailerData );
				last if( defined $Trailer->{Size} && defined $Trailer->{ID} );
			}
			push( @{$this->{Trailers}}, $Trailer );
			# Each line of Xref table contains either two numbers of the 20-byte fixed-format entry.
			# The following regexp used to be /\x0D\x0A| [\x0D\x0A]/ (changed 03/04/2002 since FDFMerge doesn't print a space after the first line of 'f'.
			my @XrefLines = split( / ?[\x0D\x0A]+/, $Buffer );
			my @MyObjOffsets = ( );	# The byte offset values recorded in this Xref table.
			my $ObjId = 0;
			for( @XrefLines ){
				if( /([\-\+\d]{10}) \d{5} ([fn])/ ){
					unless ( $2 eq 'f' ){
						push( @MyObjOffsets, $1 + 0 );
						$ObjIdByOffset{ $1 + 0 } = $ObjId;
					}
					$ObjId++;
				} elsif( /(\d+) \d+/ ){	# Doesn't care about generation id yet.
					$ObjId = $1;
				}
			}
			$EndOfTrailer = PDF::min( @MyObjOffsets );
			push( @{$this->{Boundaries}}, @MyObjOffsets );

			# If the "Prev" field is defined, then access the previous trailer; otherwise quit the while-loop.
			if( defined $Trailer->{Prev} ){
				$StartXref = $Trailer->{Prev}->[0];
				$EndOfTrailer = $MyObjOffsets[0];
				# If the previous xref is the first xref, which we have parsed, then quit.
				if( $this->{Linearized} && $StartXref == $this->{XrefOffsets}->[0] ){
					push( @{$this->{Trailers}}, splice( @{$this->{Trailers}}, 0, 2 ) );
					last;
				}
				if( $EndOfTrailer < $StartXref ){
					croak "File $filename seems corrupted because of a malformed trailer";
				}
				$this->{Revisions}++;
			} else {
				last;
			}
		}

	}	# End of 'unless' block

	# Now fill the Objects array with PObject objects
	@{$this->{Boundaries}} = sort { $a <=> $b } @{$this->{Boundaries}};
	@{$this->{XrefOffsets}} = sort { $a <=> $b } @{$this->{XrefOffsets}};

	my @Boundaries = @{$this->{Boundaries}};
	for my $offset ( @{$this->{XrefOffsets}} ){
		while( $Boundaries[0] < $offset ){
			push( @{$this->{Objects}}, new PObject( $this, @Boundaries[0..1], $ObjIdByOffset{ $Boundaries[0] } ) );
			shift( @Boundaries );
		}
		shift( @Boundaries );
	}

	# Now construct the ObjRefById (ref to an anonymous hash)
	for my $i ( reverse 0..$#{$this->{Objects}} ){
		my $obj = $this->{Objects}->[$i];
		if( !defined $this->{ObjRefById}->{ $obj->{ObjId} } ){
			$this->{ObjRefById}->{ $obj->{ObjId} } = $i;
		} elsif( !ref( $this->{ObjRefById}->{ $obj->{ObjId} } ) ){
			$this->{ObjRefById}->{ $obj->{ObjId} } = [ $this->{ObjRefById}->{ $obj->{ObjId} }, $i ];
		} else {
			push( @{$this->{ObjRefById}->{ $obj->{ObjId} }}, $i );
		}
	}

	if( !defined $this->{Trailers}->[0]->{ID} ){
		my $docinfo = $this->getDocInfo( );
		my $id;
		if( defined $docinfo ){
			$id = PDF::strToHex( &PDF::MD5( map { $docinfo->{Data}->{$_}->[0] } keys %{$docinfo->{Data}} ) );
		} else {
			$id = PDF::strToHex( &PDF::MD5( $filename, ( scalar gmtime ), rand, rand ) );
		}
		$id =~ s/^<|>$//g;
		$this->{Trailers}->[0]->{ID} = bless [
			bless( [ $id ], 'PHexStr' ),
			bless( [ $id ], 'PHexStr' ),
		], 'PArray';
	}
	return $this;
}

# Read PDF object data, given the offsets of starting and ending positions.
sub getObjectData {
	my( $this, $start, $end ) = @_;
	seek( $this->{FileHandle}, $start, SEEK_SET );
	my $Buffer;
	read( $this->{FileHandle}, $Buffer, $end - $start );
	return $Buffer;
}

# Returns the reference to a PObject by specifying its object and generation ID.
# If there's only one object for the given object ID, the generation ID is NOT checked.
# Otherwise, all objects with the same ID will be read and generation ID compared.
# But if generation ID is not provided, only the first object is returned.
sub getObjectById {
	my( $this, $ObjId, $GenId ) = @_;
	if( !defined $this->{ObjRefById}->{ $ObjId } ){
		return undef;
	} elsif( !ref( $this->{ObjRefById}->{ $ObjId } ) ){
		return $this->{Objects}->[ $this->{ObjRefById}->{ $ObjId } ];
	} else {
		my @objs = map { $this->{Objects}->[$_] } @{$this->{ObjRefById}->{ $ObjId }};
		return $objs[0] if( !defined( $GenId ) );
		for my $obj ( @objs ){
			$obj->parseIt( );
			return $obj if( $obj->{GenId} == $GenId );
		}
		return undef;
	}
}

sub getObjectByRef {
	my( $this, $pref ) = @_;
	if( ref( $pref ) ne 'PRef' ){
		return undef;
	}
	return $this->getObjectById( $pref->{ObjId}, $pref->{GenId} );
}

# Requires a file name to write into.
sub printFile {
	my( $this, $tmpfile ) = @_;
	my @XrefEntries = ( );
	$tmpfile =~ s/[\/\\]+/\//g;
	my $fh = new FileHandle;
	$fh->open( ">$tmpfile" ) or croak "Can't open file $tmpfile for output";
	my $oldout = select( $fh );
	binmode $fh;
	print "%PDF-$this->{Version}\x0D\x0A%\xE2\xE3\xCF\xD3\x0D\x0A";
	for my $ObjId ( sort { $a <=> $b } keys %{$this->{ObjRefById}} ){
		my $idx = $this->{ObjRefById}->{ $ObjId };
		$XrefEntries[ $ObjId ] = sprintf( '%010d ', tell( $fh ) );
		my $obj = $this->{Objects}->[ ref( $idx ) eq 'ARRAY'? $idx->[0]: $idx ];
		$obj->printIt( ) unless( !$obj );
		$XrefEntries[ $ObjId ] .= sprintf( '%05d n', $obj->{GenId} );
	}
	my $StartXref = tell( $fh );
	my $LastFreeEntry = 0;
	for( my $i = $#XrefEntries; $i; $i-- ){
		if( !defined( $XrefEntries[$i] ) ){
			$XrefEntries[$i] = sprintf( '%010d %05d f', $LastFreeEntry, $this->{Revisions} + 1 );
			$LastFreeEntry = $i;
		}
	}
	$XrefEntries[0] = sprintf( '%010d 65535 f', $LastFreeEntry );
	# Note each line in the xref table is exactly 20 bytes long.
	print join( "\x0D\x0A", 'xref', sprintf( '0 %d', scalar @XrefEntries ), @XrefEntries, 'trailer', '' );
	delete $this->{Trailers}->[0]->{Prev};
	PDF::printPDF( $this->{Trailers}->[0] );
	print join( $PDF::endln, '', 'startxref', $StartXref, '%%EOF' );
	$fh->close( );
	select( $oldout );
}

sub analyzePages {
	my( $this, $callback ) = @_;
	return scalar( @{$this->{PageRefs}} ) if( $this->{PagesAnalyzed} );
	my $cata = $this->getCatalog( );
	push( @{$this->{PageRefs}}, $this->getObjectByRef( $cata->{Data}->{Pages} ) );
	my $i = 0;
	my( $MediaBox, $CropBox ) = ( );
	do {
		my $pobj = $this->{PageRefs}->[$i];
		$pobj->parseIt( );
		if( exists $pobj->{Data}->{Kids} ){
			my @refs = ( );
			my $rotate;	# Added 01/30/2003 for /Rotate defined in Pages
			if( exists $pobj->{Data}->{Rotate} ){
				$rotate = $pobj->{Data}->{Rotate}->[0];
			}
			if( ref( $pobj->{Data}->{Kids} ) eq 'PRef' ){
				my $tmp = $this->getObjectByRef( $pobj->{Data}->{Kids} );
				$tmp->parseIt( );
				if( ref( $tmp->{Data} ) eq 'PArray' ){
					@refs = @{ $tmp->{Data} };
				} else {
					@refs = ( $pobj->{Data}->{Kids} );
				}
			} else {
				@refs = @{$pobj->{Data}->{Kids}};
			}
			if( exists $pobj->{Data}->{MediaBox} ){
				if( ref( $pobj->{Data}->{MediaBox} ) eq 'PRef' ){
					$MediaBox = $this->getObjectByRef( $pobj->{Data}->{MediaBox} )->parseIt( )->{Data};
				} else {
					$MediaBox = $pobj->{Data}->{MediaBox};
				}
			} else {
				$MediaBox = bless [
					bless( [ 0 ], 'PNumber' ),
					bless( [ 0 ], 'PNumber' ),
					bless( [ 612 ], 'PNumber' ),
					bless( [ 792 ], 'PNumber' ),
				], 'PArray';
			}
			if( exists $pobj->{Data}->{CropBox} ){
				if( ref( $pobj->{Data}->{CropBox} ) eq 'PRef' ){
					$CropBox = $this->getObjectByRef( $pobj->{Data}->{CropBox} )->parseIt( )->{Data};
				} else {
					$CropBox = $pobj->{Data}->{CropBox};
				}
			} elsif( !$CropBox ){
				$CropBox = $MediaBox;
			}
			if( scalar @refs ){
				splice( @{$this->{PageRefs}}, $i, 1,
					map { $this->getObjectByRef( $_ ); } @refs );
				foreach my $kid ( @{$this->{PageRefs}}[ $i .. ( $i + scalar @refs - 1 ) ] ){
					$kid->parseIt( );
					if( defined $callback && ref( $callback ) eq 'CODE' ){
						&$callback( { 'PNum' => $i + 1, 'PTotal' => scalar @{$this->{PageRefs}} } );
					}
					if( !exists $kid->{Data}->{MediaBox} ){
						$kid->{Data}->{MediaBox} = &PDF::copyPDF( $pobj, $MediaBox, {} );
						if( !exists $kid->{Data}->{CropBox} ){
							$kid->{Data}->{CropBox} = &PDF::copyPDF( $pobj, $CropBox, {} );
						} else {
							$CropBox = $kid->{Data}->{CropBox};
						}
					} else {
						if( !exists $kid->{Data}->{CropBox} ){
							$CropBox = $kid->{Data}->{MediaBox};
							$kid->{Data}->{CropBox} = &PDF::copyPDF( $pobj, $CropBox, {} );
						} else {
							$CropBox = $kid->{Data}->{CropBox};
						}
					}
					if( exists $pobj->{Data}->{Resources} && !exists $kid->{Data}->{Resources} ){
						$kid->{Data}->{Resources} = $pobj->{Data}->{Resources};
					}
					if( defined $rotate && !exists $kid->{Data}->{Rotate} ){
						$kid->{Data}->{Rotate} = bless [ $rotate ], 'PNumber';
					}
				}
			}
		} else {
			$i++;
		}
		if( defined $callback && ref( $callback ) eq 'CODE' ){
			&$callback( { 'PNum' => $i + 1, 'PTotal' => scalar @{$this->{PageRefs}} } );
		}
	} while( $i < scalar @{$this->{PageRefs}} );
	for $i ( 1..scalar @{$this->{PageRefs}} ){
		$this->{PageRefs}->[ $i-1 ]->{PageNumber} = $i;
	}
	if( defined $callback && ref( $callback ) eq 'CODE' ){
		&$callback( { 'PNum' => $i, 'PTotal' => $i } );
	}
	my $n = scalar( @{$this->{PageRefs}} );
	for( 0..$n-1 ){
		$this->{PageOrders}->{ $this->{PageRefs}->[$_] } = $_;
	}
	$this->{PagesAnalyzed} = 1;
	return $n;
}

sub getPageOrder {
	my( $this, $pgref ) = @_;
	$this->analyzePages( );
	if( ref $pgref eq 'PRef' ){
		$pgref = $this->getObjectByRef( $pgref );
	}
	# Fixed 10/03/2002: Should return -1 to indicate "not found".
	# Fixed 10/07/2002: Check the hash directly rather than sequential lookup.
	return ( exists $this->{PageOrders}->{$pgref}? $this->{PageOrders}->{$pgref}: -1 );
}

sub getEncryptState {
	my $this = shift;
	return defined $this->{Trailers}->[0]->{Encrypt};
}

sub getLinearizeState {
	return shift->{Linearized};
}

sub getUpdateState {
	my $this = shift;
	return scalar @{$this->{Trailers}} - $this->{Linearized} - 1;
}

sub getPageCount {
	my $this = shift;
	return $this->analyzePages( );
}

sub getObjectCount {
	my $this = shift;
	return scalar @{$this->{Objects}};
}

sub getDocInfo {
	my $this = shift;
	if( defined $this->{Trailers}->[0]->{Info} ){
		return $this->getObjectByRef( $this->{Trailers}->[0]->{Info} )->parseIt( );
	} elsif( $this->getEncryptState( ) ){
		return undef;
	} else {
		my $info = new PObject( $this, 0, 0, PDF::max( keys %{$this->{ObjRefById}} ) + 1 );
		$this->{ObjRefById}->{ $info->{ObjId} } = scalar @{$this->{Objects}};
		push( @{$this->{Objects}}, $info );
		$info->{Parsed} = 1;	# So that parseIt( ) will not try to read from file.
		$info->{Data} = bless {
			Creator => ( bless [ 'PDFeverywhere 3.0' ], 'PCharStr' ),
		}, 'PDict';
		$this->{Trailers}->[0]->{Info} = bless { ObjId => $info->{ObjId}, GenId => 0 }, 'PRef';
		$this->{Trailers}->[0]->{Size}->[0]++;
		return $info;
	}
}

# Used by getTitle, getAuthor, getSubject, ...
sub getDocInfoField {
	my( $this, $field ) = @_;
	my $info = $this->getDocInfo( );
	if( !$info || !exists $info->{Data}->{$field} ){
		return '';
	}
	return $info->{Data}->{$field}->getStr( );
}

sub setDocInfoField {
	my( $this, $field, $value ) = @_;
	my $info = $this->getDocInfo( );
	return if( !$info );
	if( exists $info->{Data}->{$field} ){
		if( ref( $info->{Data}->{$field} ) eq 'PCharStr' ){
			$info->{Data}->{$field}->[0] = $value;
		} else {	# Must be PHexStr
			$info->{Data}->{$field}->[0] = PDF::strToHex( $value );
			$info->{Data}->{$field}->[0] =~ s/^<|>$//g;
		}
	} else {
		$info->{Data}->{$field} = ( bless [ $value ], 'PCharStr' );
	}
}

sub getTitle {
	return shift->getDocInfoField( 'Title' );
}

sub setTitle {
	my $this = shift;
	$this->setDocInfoField( 'Title', shift );
}

sub getAuthor {
	return shift->getDocInfoField( 'Author' );
}

sub setAuthor {
	my $this = shift;
	$this->setDocInfoField( 'Author', shift );
}

sub getSubject {
	return shift->getDocInfoField( 'Subject' );
}

sub setSubject {
	my $this = shift;
	$this->setDocInfoField( 'Subject', shift );
}

sub getKeywords {
	return shift->getDocInfoField( 'Keywords' );
}

sub setKeywords {
	my $this = shift;
	$this->setDocInfoField( 'Keywords', shift );
}

sub getProducer {
	return shift->getDocInfoField( 'Producer' );
}

sub setProducer {
	my $this = shift;
	$this->setDocInfoField( 'Producer', shift );
}

sub getCreator {
	return shift->getDocInfoField( 'Creator' );
}

sub setCreator {
	my $this = shift;
	$this->setDocInfoField( 'Creator', shift );
}

sub getCatalog {
	my $this = shift;
	return $this->getObjectByRef( $this->{Trailers}->[0]->{Root} )->parseIt( );
}

sub getEncryptDict {
	my $this = shift;
	if( $this->getEncryptState( ) ){
		return $this->getObjectByRef( $this->{Trailers}->[0]->{Encrypt} )->parseIt( );
	} else {
		return 0;
	}
}

sub getAcroForm {
	my $this = shift;
	my $catalog = $this->getCatalog( );
	$catalog->parseIt( );
	# Here the AcroForm is required to be an indirect reference; may be changed to allow a dictionary
	if( !exists( $catalog->{Data}->{AcroForm} ) || ref( $catalog->{Data}->{AcroForm} ) ne 'PRef' ){
		return undef;
	}
	return $this->getObjectByRef( $catalog->{Data}->{AcroForm} )->parseIt( );
}

sub analyzeNames {
	my $this = shift;
	return if( $this->{NamesAnalyzed} );
	$this->{NamesAnalyzed} = 1;
	my $cata = $this->getCatalog( );
	if( !exists $cata->{Data}->{Names} ){	# PDF 1.2 feature
		return if( !exists $cata->{Data}->{Dests} );	# PDF 1.1 feature; must be an indirect ref
		my $data = $this->getObjectByRef( $cata->{Data}->{Dests} )->parseIt( )->{Data};
		for( keys %$data ){
			$this->{Names}->{$_} = ref $data->{$_} eq 'PArray'?	# Either PArray or PRef
				$data->{$_}:
				$this->getObjectByRef( $data->{$_} )->parseIt( )->{Data}->{D};	# Fixed Apr 13 2002: added "->{D}"
		}
		return;
	}
	my $p = $cata->{Data}->{Names};
	if( ref( $p ) eq 'PRef' ){
		$p = $this->getObjectByRef( $p )->parseIt( )->{Data};
	}
	# Now $p points to the names dictionary
	return if( ref( $p ) ne 'PDict' || !exists $p->{Dests} );	# Destinations defined?
	$p = $p->{Dests};
	if( ref( $p ) eq 'PRef' ){
		$p = $this->getObjectByRef( $p )->parseIt( )->{Data};
	}
	# Now $p points to the destinations dictionary (names tree root node)
	# Each node in the names tree can have a Names or Kids entry but not both
	my @kids = ( $p );
	while( @kids ){
		$p = shift @kids;
		if( exists $p->{Names} ){
			my $q = $p->{Names};
			if( ref( $q ) eq 'PRef' ){
				$q = $this->getObjectByRef( $q )->parseIt( )->{Data};
			}
			# Now $q points to an array of name/ref pairs
			my @pairs = @$q;
			while( my( $n, $r ) = splice( @pairs, 0, 2 ) ){
				next if( ref $r eq 'PName' );	# In this case, the dest is "null"
				# $n is a PCharStr; $r is a PRef, whose PObject is (1) a PDict containing a key 'D',
				# whose value is a PArray; or (2) a PArray as the direct definition
				my $pref = $this->getObjectByRef( $r );
				next if( !defined $pref );
				$pref = $pref->parseIt( )->{Data};
				if( ref( $n ) eq 'PRef' ){
					$n = $this->getObjectByRef( $n );
					next if( !defined $n );
					$n = $n->parseIt( )->{Data};
				}
				if( ref( $pref ) eq 'PDict' ){
					$this->{Names}->{ $n->getStr( ) } = $pref->{D};
				} else {
					$this->{Names}->{ $n->getStr( ) } = $pref;
				}
			}
		} elsif( exists $p->{Kids} ){
			my $q = $p->{Kids};
			if( ref( $q ) eq 'PRef' ){
				$q = $this->getObjectByRef( $q )->parseIt( )->{Data};
			}
			push( @kids, map { $this->getObjectByRef( $_ )->parseIt( )->{Data} } @$q );
		}
	}
}

sub getNames {
	my $this = shift;
	$this->analyzeNames( );
	return $this->{Names};
}

# $referred is an external hash reference, which will be filled;
# @numbers are the page numbers, starting from 0;
# Returns two array refs: one to the copied page objects, the other to all.
# All objects are duplicates; the original remain intact.
sub copyPages {
	my( $this, $referred, @numbers ) = @_;
	$this->analyzePages( );
	$this->analyzeNames( );
	$referred ||= { };
	my @PageObjs = ( );
	@PObject::CopiedObjects = ( );
	for my $i ( @numbers ){
		my $obj = $this->{PageRefs}->[ $i ];	# PObject for the page
		if( exists $referred->{ $obj } ){	# If the page has been copied by this PDFDoc ...
			push( @PageObjs, $referred->{ $obj } );	# then skip copying
		} else {
			$obj->parseIt( );
			# We can't allow an annotation to point to another page, which would be copied!
			if( exists $obj->{Data}->{Annots} ){
				my $ann = $obj->{Data}->{Annots};
				if( ref $ann eq 'PRef' ){
					$ann = $this->getObjectByRef( $ann )->parseIt( )->{Data};
				}
				for my $aref ( @$ann ){	# 08/20/2002: $aref usually is a PRef, but it could be a direct PDict, though rare
					if( ref( $aref ) eq 'PRef' ){
						my $data = $this->getObjectByRef( $aref )->parseIt( )->{Data};
						$data->{Type} = bless [ 'Annot' ], 'PName';
					} else {
						$aref->{Type} = bless [ 'Annot' ], 'PName';
					}
				}
			}
			my $pg = $obj->copyIt( $referred );
			push( @PageObjs, $pg );
		}
	}
	my @CopiedObjects = @PObject::CopiedObjects;
	@PObject::CopiedObjects = ( );
	return ( \@PageObjs, \@CopiedObjects );
}

sub copyCatalogObject {
	my( $this, $type, $referred ) = @_;
	my $cata = $this->getCatalog( );
	if( !exists $cata->{Data}->{$type} ){
		return ( undef, undef );
	}
	my $ptr;
	@PObject::CopiedObjects = ( );
	my $obj = $cata->{Data}->{$type};
	if( exists $referred->{ $obj } ){	# Copied before
		$ptr = $referred->{ $obj };
	} elsif( ref( $obj ) eq 'PRef' ){	# Indirect reference
		$obj = $this->getObjectByRef( $obj )->parseIt( );
		$ptr = $obj->copyIt( $referred );
	} else {	# Direct data (PDict, PArray, etc.)
		$ptr = PDF::copyPDF( $cata, $obj, $referred );
	}
	my @CopiedObjects = @PObject::CopiedObjects;
	@PObject::CopiedObjects = ( );
	return ( $ptr, \@CopiedObjects );
	# Note $ptr can be a PObject or a PDict, PArray, etc.
}

sub copyNames {
	my( $this, $referred ) = @_;
	return $this->copyCatalogObject( 'Names', $referred );
}

# Page number is 0-based
sub setOpenPage {
	my $this = shift;
	$this->analyzePages( );
	my $pagenum = shift( @_ );
	return if( $pagenum < 0 || $pagenum >= scalar @{$this->{PageRefs}} );
	my $page = $this->{PageRefs}->[ $pagenum ];
	$page->parseIt( );
	my $cata = $this->getCatalog( );
	$cata->{Data}->{OpenAction} = bless [
		bless( { ObjId => $page->{ObjId}, GenId => $page->{GenId} }, 'PRef' ),
		bless( [ 'Fit' ], 'PName' ),
	], 'PArray';
}

sub setViewerPref {
	my( $this, $attr ) = @_;
	my $cata = $this->getCatalog( );
	my $vpref = bless { }, 'PDict';
	for( qw(Toolbar Menubar WindowUI FitWindow CenterWindow) ){
		if( exists $attr->{$_} ){
			$vpref->{$_} = bless( [ $attr->{$_}? 'true': 'false' ], 'PName' );
		}
	}
	$cata->{Data}->{ViewerPreferences} = $vpref;
}

sub setPageLayout {
	my( $this, $layout ) = @_;
	my $cata = $this->getCatalog( );
	$cata->{Data}->{PageLayout} = bless [ $layout ], 'PName';
}

sub setPageMode {
	my( $this, $mode ) = @_;
	my $cata = $this->getCatalog( );
	$cata->{Data}->{PageMode} = bless [ $mode ], 'PName';
}

sub setPageDuration {
	my( $this, $pagenum, $dur ) = @_;
	$this->analyzePages( );
	return if( $pagenum < 0 || $pagenum > scalar @{$this->{PageRefs}} );
	my $page = $this->{PageRefs}->[ $pagenum - 1 ];
	$page->parseIt( );
	$page->{Data}->{Dur} = bless [ $dur ], 'PNumber';
}

sub setPageTransition {
	my( $this, $pagenum, $trans, $attr ) = @_;
	$this->analyzePages( );
	return if( $pagenum < 0 || $pagenum > scalar @{$this->{PageRefs}} );
	my $page = $this->{PageRefs}->[ $pagenum - 1 ];
	$page->parseIt( );
	my $tdict = bless { S => bless( [ $trans ], 'PName' ) }, 'PDict';
	if( exists $attr->{TransDur} ){ $tdict->{Dur} = bless [ $attr->{TransDur} ], 'PNumber'; }
	if( exists $attr->{Dimension} ){ $tdict->{Dm} = bless [ $attr->{Dimension} ], 'PName'; }
	if( exists $attr->{Direction} ){ $tdict->{Di} = bless [ $attr->{Direction} ], 'PName'; }
	if( exists $attr->{Motion} ){ $tdict->{M} = bless [ $attr->{Motion} ], 'PName'; }
	$page->{Data}->{Trans} = $tdict;
}

# Added 01/27/2003
sub getDirectData {
	my( $this, $pref ) = @_;
	if( ref( $pref ) eq 'PRef' ){
		return $this->getObjectByRef( $pref )->parseIt( )->{Data};
	}
	return $pref;
}

# Encrypt a PDF file. $setting is a hash ref that contains the following keys:
# OwnerPwd, UserPwd, Print, Change, Select, ChangeAll
sub encrypt {
	my( $this, $setting, $callback ) = @_;
	if( exists $this->{Trailers}->[0]->{Encrypt} ){
		croak "File $this->{FileName} has already been encrypted";
	}
	my $perm = 0xFFFFFFC0;
	$setting->{Print} && do { $perm |= 4; };		# Bit 3
	$setting->{Change} && do { $perm |= 8; };		# Bit 4
	$setting->{Select} && do { $perm |= 16; };		# Bit 5
	$setting->{ChangeAll} && do { $perm |= 32; };	# Bit 6
	if( $setting->{StrongEnc} ){
		$setting->{LockForm} && do { $perm ^= 256; };		# Bit 9
		$setting->{NoAccess} && do { $perm ^= 512; };		# Bit 10
		$setting->{NoAssembly} && do { $perm ^= 1024; };		# Bit 11
		$setting->{PrintAsImage} && do { $perm ^= 2048; $perm |= 4; };	# Bit 12
	}
	if( !exists $setting->{Owner} ){
		$setting->{Owner} = '';
	}
	if( !exists $setting->{User} ){
		$setting->{User} = '';
	}
	$this->{OwnerPwd} = PDF::padPwd( length( $setting->{Owner} )? $setting->{Owner}: $setting->{User} );
	$this->{UserPwd} = PDF::padPwd( $setting->{User} );
	my( $EOwner, $EUser );
	my $fileID = $this->{Trailers}->[0]->{ID}->[0]->getStr( );
	$setting->{StrongEnc} ||= 0;
	if( $setting->{StrongEnc} ){
		my $RCkey = $this->{OwnerPwd};
		for( 1..51 ){	# MD5 for 51 times in total
			$RCkey = PDF::MD5( $RCkey );
		}
		my $input = $this->{UserPwd};
		my $output = PDF::RC4( $RCkey, $input );
		my @chars = split( //, $RCkey );
		my $temp;
		for my $i ( 1..19 ){
			$input = $output;
			$temp = join( '', map { chr( ord( $_ ) ^ $i ) } @chars );
			$output = &PDF::RC4( $temp, $input );
		}
		$EOwner = $output;
		$temp = &PDF::MD5( $this->{UserPwd}, $EOwner, pack( 'V', $perm ), $fileID );
		for( 1..50 ){ $temp = &PDF::MD5( $temp ); }
		$this->{EKey} = $temp;
		$input = &PDF::MD5( $PDF::PadChars, $fileID );
		$output = &PDF::RC4( $this->{EKey}, $input );
		@chars = split( //, $this->{EKey} );
		for my $i ( 1..19 ){
			$input = $output;
			$temp = join( '', map { chr( ord( $_ ) ^ $i ) } @chars );
			$output = &PDF::RC4( $temp, $input );
		}
		$EUser = $output . ( chr( 0 ) x 16 );
		if( $this->{Version} < 1.4 ){ $this->{Version} = '1.4'; }
	} else {
		$EOwner = PDF::RC4( substr( PDF::MD5( $this->{OwnerPwd} ), 0, 5 ), $this->{UserPwd} );
		$this->{EKey} = substr( PDF::MD5( $this->{UserPwd}, $EOwner, pack( 'V', $perm ), $fileID ), 0, 5 );
		$EUser = PDF::RC4( $this->{EKey}, $PDF::PadChars );
	}
	my $currlen = 0;
	for my $pobj ( @{$this->{Objects}} ){
		next if( !defined $pobj );
		$pobj->parseIt( );
	}
	for my $pobj ( @{$this->{Objects}} ){
		next if( !defined $pobj );
		if( defined $callback && ref( $callback ) eq 'CODE' ){
			$currlen += ( $pobj->{End} - $pobj->{Start} );
			&$callback( { ObjId => $pobj->{ObjId}, CurrLen => $currlen, TotalLen => $this->{Length} } );
		}
		$pobj->encryptIt( $this->{EKey}, $setting->{StrongEnc} );
	}
	my $enc = new PObject( $this, 0, 0, PDF::max( keys %{$this->{ObjRefById}} ) + 1 );
	$this->{ObjRefById}->{ $enc->{ObjId} } = scalar @{$this->{Objects}};
	push( @{$this->{Objects}}, $enc );
	$enc->{Parsed} = 1;
	$enc->{Data} = bless {
		Filter => ( bless [ 'Standard' ], 'PName' ),
		V => ( bless [ $setting->{StrongEnc}? 2: 1 ], 'PNumber' ),
		R => ( bless [ $setting->{StrongEnc}? 3: 2 ], 'PNumber' ),
		P => ( bless [ $perm - 4294967296 ], 'PNumber' ),
		O => ( bless [ $EOwner ], 'PCharStr' ),
		U => ( bless [ $EUser ], 'PCharStr' ),
	}, 'PDict';
	if( $setting->{StrongEnc} ){
		$enc->{Data}->{Length} = bless [ 128 ], 'PNumber';
	}
	$this->{Trailers}->[0]->{Encrypt} = $enc;
	$this->{Trailers}->[0]->{Size}->[0]++;
}

# Decrypt an encrypted PDF file.
sub decrypt {
	my( $this, $ownerpwd, $callback ) = @_;
	if( !defined $ownerpwd ){
		$ownerpwd = '';
	}
	if( !exists $this->{Trailers}->[0]->{Encrypt} ){
		croak "File $this->{FileName} is NOT encrypted";
	}
	my $pobj = $this->getObjectById( $this->{Trailers}->[0]->{Encrypt}->{ObjId}, $this->{Trailers}->[0]->{Encrypt}->{GenId} );
	$pobj->parseIt( );
	my $strong = undef;
	if( $pobj->{Data}->{Filter}->[0] eq 'Standard' ){
		if( $pobj->{Data}->{V}->[0] == 1 || $pobj->{Data}->{R}->[0] == 2 ){
			$strong = 0;
		} elsif( $pobj->{Data}->{V}->[0] == 2 || $pobj->{Data}->{R}->[0] == 3 ){
			$strong = 1;
		}
	}
	if( !defined $strong ){
		croak "Cannot decrypt $this->{FileName} because of unrecognized encryption method";
	}
	if( $strong == 1 && $pobj->{Data}->{Length}->[0] != 128 ){
		croak "Cannot decrypt $this->{FileName} using strong encryption with non-128-bit";
	}
	my( $EOwner, $EUser );
	if( $strong ){
		my $RCkey = PDF::padPwd( $ownerpwd );
		for( 1..51 ){	# MD5 for 51 times in total
			$RCkey = PDF::MD5( $RCkey );
		}
		my $output = $pobj->{Data}->{O}->getStr( );
		my( $input, $temp );
		my @chars = split( //, $RCkey );
		for my $i ( reverse 0..19 ){
			$input = $output;
			$temp = join( '', map { chr( ord( $_ ) ^ $i ) } @chars );
			$output = &PDF::RC4( $temp, $input );
		}
		$EUser = $output;
		$temp = &PDF::MD5( $EUser, $pobj->{Data}->{O}->getStr( ), pack( 'V', $pobj->{Data}->{P}->[0] + 4294967296 ),
			$this->{Trailers}->[0]->{ID}->[0]->getStr( ) );
		for( 1..50 ){ $temp = &PDF::MD5( $temp ); }
		$this->{EKey} = $temp;
		$input = PDF::MD5( $PDF::PadChars, $this->{Trailers}->[0]->{ID}->[0]->getStr( ) );
		$output = &PDF::RC4( $this->{EKey}, $input );
		@chars = split( //, $this->{EKey} );
		for my $i ( 1..19 ){
			$input = $output;
			$temp = join( '', map { chr( ord( $_ ) ^ $i ) } @chars );
			$output = &PDF::RC4( $temp, $input );
		}
		if( index( $pobj->{Data}->{U}->getStr( ), $output ) < 0 ){
			croak "Incorrect password supplied for $this->{FileName}";
		}
	} else {
		$EOwner = PDF::RC4( substr( PDF::MD5( PDF::padPwd( $ownerpwd ) ), 0, 5 ), $pobj->{Data}->{O}->getStr( ) );
		my $permvalue = $pobj->{Data}->{P}->[0] + 0;
		if( $permvalue > 0 ){
			$permvalue = 4294967296 - 65536 + $permvalue;	# Fixed 07/24/02: in the rare case P may be a positive 16-bit int
		} else {
			$permvalue += 4294967296;
		}
		$this->{EKey} = substr( PDF::MD5( $EOwner, $pobj->{Data}->{O}->getStr( ), pack( 'V', $permvalue ),
			$this->{Trailers}->[0]->{ID}->[0]->getStr( ) ), 0, 5 );
		if( PDF::RC4( $this->{EKey}, $pobj->{Data}->{U}->getStr( ) ) ne $PDF::PadChars ){
			# Fixed 11/09/2002: Sometimes a positive P value is used as-is! Not always converted to negative value! So we try again here.
			$permvalue = $pobj->{Data}->{P}->[0] + 0;
			if( $permvalue > 0 ){
				$this->{EKey} = substr( PDF::MD5( $EOwner, $pobj->{Data}->{O}->getStr( ), pack( 'V', $permvalue ),
					$this->{Trailers}->[0]->{ID}->[0]->getStr( ) ), 0, 5 );
				if( PDF::RC4( $this->{EKey}, $pobj->{Data}->{U}->getStr( ) ) ne $PDF::PadChars ){
					croak "Incorrect password supplied for $this->{FileName}";
				}
			} else {
				croak "Incorrect password supplied for $this->{FileName}";
			}
		}
	}
	my $idx = $this->{ObjRefById}->{ $pobj->{ObjId} };
	if( ref( $idx ) eq 'ARRAY' ){
		$idx = $idx->[0];
	}
	$this->{Objects}->[ $idx ] = undef;
	delete $this->{ObjRefById}->{ $pobj->{ObjId} };
	delete $this->{Trailers}->[0]->{Encrypt};
	my $currlen = 0;
	for $pobj ( @{$this->{Objects}} ){
		next if( !defined $pobj );
		if( defined $callback && ref( $callback ) eq 'CODE' ){
			$currlen += ( $pobj->{End} - $pobj->{Start} );
			&$callback( { ObjId => $pobj->{ObjId}, CurrLen => $currlen, TotalLen => $this->{Length} } );
		}
		$pobj->parseIt( );
		$pobj->encryptIt( $this->{EKey}, $strong );
	}
}

sub finalize {
	my $this = shift;
	@{$this->{PageRefs}} = ( );
	for( keys %{$this->{ObjRefById}} ){
		if( ref $this->{ObjRefById}->{$_} eq 'ARRAY' ){
			@{$this->{ObjRefById}->{$_}} = ( );
		}
	}
	%{$this->{ObjRefById}} = ( );
	for( keys %{$this->{Names}} ){
		@{$this->{Names}->{$_}} = ( );
	}
	%{$this->{Names}} = ( );
	@{$this->{Trailers}} = ( );
	for( @{$this->{Objects}} ){
		$_->finalize( ) if( defined $_ && ref( $_ ) eq 'PObject' );
	}
	@{$this->{Objects}} = ( );
	%$this = ( );
}

sub destroy {
	PDF::removePDFFile( shift );
}

sub DESTROY {
	PDF::removePDFFile( shift );
}

1;