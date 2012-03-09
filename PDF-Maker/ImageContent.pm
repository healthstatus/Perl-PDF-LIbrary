#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#

package ImageContent;

use PDFStream;
use FileHandle;
use Bit::Vector;

@ISA = qw(PDFStream);

%TIFTagTranslate = (
	254 => 'NewSubfileType',
	255 => 'SubfileType',
	256 => 'ImageWidth',
	257 => 'ImageLength',
	258 => 'BitsPerSample',
	259 => 'Compression',
	262 => 'PhotometricInterpretation',
	263 => 'Thresholding',
	264 => 'CellWidth',
	265 => 'CellLength',
	266 => 'FillOrder',
	273 => 'StripOffsets',
	277 => 'SamplesPerPixel',
	278 => 'RowsPerStrip',
	279 => 'StripByteCounts',
	280 => 'MinSampleValue',
	281 => 'MaxSampleValue',
	282 => 'XResolution',
	283 => 'YResolution',
	284 => 'PlanarConfiguration',
	288 => 'FreeOffsets',
	289 => 'FreeByteCounts',
	291 => 'GreyResponseCurve',
	292 => 'T4Options',
	293 => 'T6Options',
	296 => 'ResolutionUnit',
	301 => 'ColorResponseCurves',
	317 => 'Predictor',
	318 => 'WhitePoint',
	319 => 'PrimaryChromaticities',
	320 => 'ColorMap',
	321 => 'HalftoneHints',
	322 => 'TileWidth',
	323 => 'TileLength',
	324 => 'TileOffset',
	325 => 'TileByteCounts',
	336 => 'DotRange',
# Following tags are used in Exif format
	513 => 'JPEGInterchangeFormat',
	514 => 'JPEGInterchangeFormatLength',
	6657 => 'XResolution',
	6913 => 'YResolution',
	34665 => 'ExifIFD',
	37122 => 'CompressedBitsPerPixel',
	40961 => 'ColorSpace',
	40962 => 'PixelXDimension',
	40963 => 'PixelYDimension',
);

sub new {
	my( $class, $File, $width, $height, $attr ) = @_;
	my $this = {
		'ObjId' => 0,
		'Width' => $width,
		'Height' => $height,
		'BitsPerComponent' => 8,	# Default, unless overwritten by data retrieved from image file
		'ColorSpace' => '',
		'ColorTable' => 0,	# Always a PDFStream object
		'DisplayWidth' => &PDF::tellSize( $width ),
		'DisplayHeight' => &PDF::tellSize( $height ),
		'Filters' => [ ],
		'DecodeParms' => [ ],
		'Stream' => '',
		'Length' => 0,
		'Mask' => undef,
		'MaskDecode' => [ ],
		'Decode' => [ ],
		'Name' => '',
		'Inline' => $attr->{Inline},
		'File' => $File,
		'XML' => [ ],
		'FileHandle' => undef,	# The following 4 keys for disk-based storage
		'StreamStart' => 0,
		'StreamLength' => 0,
		'DiskBased' => 0,
	};
	bless $this, $class;
	$this->setName( $attr->{Name} );
	if( ref( $File ) eq 'PDFStream' ){	# Internal image data
		$this->{DisplayWidth} = $this->{Width} = $width;
		$this->{DisplayHeight} = $this->{Height} = $height;
		$this->{BitsPerComponent} = $attr->{BitsPerComponent};
		push( @{$this->{Filters}}, @{$File->{Filters}} );
		push( @{$this->{DecodeParms}}, @{$File->{DecodeParms}} );
		if( $attr->{Type} eq 'Indexed' ){
			if( $attr->{Colors} ){
				$this->{ColorTable} = new PDFStream( join( '', map{ chr( int( $_ * 255 ) ) } (
					map { &Color::tellColor( $_, 'RGB' ) } @{$attr->{Colors}}
				) ) );
			} elsif( $attr->{ColorTable} ){
				$this->{ColorTable} = new PDFStream( $attr->{ColorTable} );
			}
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageI', 'ImageC' );
		} else {
			$this->{ColorSpace} = 'Device' . $attr->{Type};
			$PDF::root->getPagesRoot( )->setProcSet( $attr->{Type} eq 'Gray'? 'ImageG': 'ImageC' );
		}
		$PDF::root->getPagesRoot( )->appendImage( $this ) unless( $this->{Inline} );
		$this->{Stream} = $File->{Stream};
		return $this;
	}
	my( $ImgData, $OK ) = ( );
	$File = &PDF::secureFileName( $File );
	my $fh = new FileHandle( "<$File" ) ;
	if( $fh ){
		$OK = 1;
		binmode $fh;
		local $/ = undef;
		$ImgData = <$fh>;
		close( $fh );
	}
	unless( $OK ){
		if( $PDF::root->{Prefs}->{SkipBadImage} ){
			return $this->setErrorImage( );
		} else {
			die "Can't open image file $File";
		}
	}
	if( $ImgData =~ m{^GIF8[7|9]a} ){
		$this->{Mode} = 'GIF';
	} elsif( $ImgData =~ m{^\x89PNG\x0D\x0A\x1A\x0A} ){
		$this->{Mode} = 'PNG';
	} elsif( $ImgData =~ m{^\xFF\xD8\xFF\xE0..JFIF}s ){
		$this->{Mode} = 'JPG';
	} elsif( $ImgData =~ m{^\xFF\xD8\xFF\xE1..Exif}s ){
		$this->{Mode} = 'EXIF';
	} elsif( $ImgData =~ m{^BM} ){
		$this->{Mode} = 'BMP';
	} elsif( $ImgData =~ m{^II\*\x00} || $ImgData =~ m{^MM\x00\*} ){
		$this->{Mode} = 'TIF';
	} elsif( $File =~ m{\.(TGA|VDA|ICB|VST|TPIC)$}i ){
		$this->{Mode} = 'TGA';
	} elsif( $File =~ m{\.PCX$}i && $ImgData =~ m{^\x0A} ){
		$this->{Mode} = 'PCX';
	}
	if( $this->{Mode} eq 'GIF' ){
		my $GIFHeader = substr( $ImgData, 0, 13, '' );
		$this->{Width} = unpack( 'S', substr( $GIFHeader, 6, 2 ) );
		$this->{Height} = unpack( 'S', substr( $GIFHeader, 8, 2 ) );
		$this->{BitsPerComponent} = ( unpack( 'C', substr( $GIFHeader, 10, 1 ) ) & 7 ) + 1;
		$PDF::root->getPagesRoot( )->setProcSet( 'ImageI', 'ImageC' );
		my $GIFPalette = substr( $ImgData, 0, ( 2 ** $this->{BitsPerComponent} ) * 3, '' );
		if( $this->{BitsPerComponent} != 8 ){
			if( $PDF::root->{Prefs}->{SkipBadImage} ){ return $this->setErrorImage( ); } else { die "$File: non-256-color GIF images not supported." };
		}
		$this->{ColorTable} = new PDFStream( $GIFPalette );
		$this->setFilter( 'LZWDecode', '<< /EarlyChange 0 >>' );
		my( $InData, $BitsPerCode, $TableSize, $Threshold ) = ( 0, 9, 0, 257 );
		my( $c, $LZWMiniCodeSize, $Buffer, $CodeLen );
		my $vtmp = new Bit::Vector( 9 );
		my $vOut = new Bit::Vector( 4096 );
		my $vIn  = new Bit::Vector( 0 );
		my $j = 4096;
		OUTER: while( 1 ){
			$c = substr( $ImgData, 0, 1, '' );
			if( !$InData ){
				if( $c eq "\x21" ){				# Extensions
					$c = substr( $ImgData, 0, 1, '' );
					if( $c eq "\xF9" ){			# Graphic Control Extension
						my @gcs = unpack( 'CCSCC', substr( $ImgData, 0, 6, '' ) );
# Temporarily commented out since masked images are not displayed properly in Acrobat 5
#						if( $gcs[1] % 2 ){		# Transparency flag is the least significant bit of this byte
#							my @transp = split( //, substr( $GIFPalette, $gcs[4] * 3, 3 ) );
#							push( @{$this->{MaskDecode}}, ( map{ unpack( 'C', $_ ) } ( @transp[0,0,1,1,2,2] ) ) );
#						}
					} elsif( $c eq "\xFE" ){	# Comment Extension
						substr( $ImgData, 0, index( $ImgData, "\x00" ) + 1, '' );
					} else {					# Plain Text Extension or Application Extension
						# First, skip the descriptor portion
						substr( $ImgData, 0, ( $c eq "\xFF"? 13: 12 ), '' );
						# Then skip the data portion -- assume there is no zero in the application data
						substr( $ImgData, 0, index( $ImgData, "\x00" ) + 1, '' );
					}
				} elsif( $c eq "\x2C" ){		# Image Descriptor
					my $ImageDescriptor = substr( $ImgData, 0, 9, '' );
					# Note: The following a few lines should yield the same values read from file header
					# my ( $w1, $w2, $h1, $h2 ) = split( //, substr( $ImageDescriptor, 4, 4 ) );
					# $this->{Width} = unpack( "C", $w1 ) + unpack( "C", $w2 ) * 256;
					# $this->{Height} = unpack( "C", $h1 ) + unpack( "C", $h2 ) * 256;
					my $PackedField = unpack( "C", substr( $ImageDescriptor, -1 ) );
					if( $PackedField & 0xC0 ){
						if( $PDF::root->{Prefs}->{SkipBadImage} ){ return $this->setErrorImage( ); } else { die "$File: Local color table and interlacing in GIF images not supported." };
					}
				} else {
					$InData = 1;
					$LZWMiniCodeSize = unpack( "C", $c );	# Critical: Must be 8!
				}
				next;
			} else {
				$CodeLen = unpack( "C", $c );	# Max length of each data chunk is 255 bytes
				if( $CodeLen ){
					# Out task is to find the variable-length codes and stack them together again so Acrobat can decode them.
					# First, turn the byte stream, in reserved order, into a bit stream; residue from last run are at right-most side.
					my $vect = Bit::Vector->new_Hex( $CodeLen * 8 + $vIn->Size( ), unpack( 'H*', reverse substr( $ImgData, 0, $CodeLen, '' ) ) );
					my $k = $vIn->Size( );
					if( $k ){
						$vect->Move_Left( $k );
						$vect->Interval_Copy( $vIn, 0, 0, $k );
					}
					$vIn = $vect;
					$k = $vIn->Size( );	# Renew the value
					my $i = 0;
					while( $i + $BitsPerCode < $k ){
						$TableSize++;
						if( $TableSize == $Threshold ){
							$vtmp->Resize( ++$BitsPerCode );
							$Threshold = 2 ** $BitsPerCode + 1 - 256;
						}
						$vtmp->Interval_Copy( $vIn, 0, $i, $BitsPerCode );	# Use a temp var so that we can determine its value
						$i += $BitsPerCode;
						if( $j >= $BitsPerCode ){
							# Does nothing
						} elsif( $j ){
							my $vrmd = new Bit::Vector( ( int( $j / 8 ) + 1 ) * 8 );
							$vrmd->Interval_Copy( $vOut, 0, 0, $vrmd->Size( ) );
							$vOut->Move_Right( $vrmd->Size( ) );
							$vOut->Resize( $vOut->Size( ) - $vrmd->Size( ) );
							$this->{Stream} .= pack( 'H*', $vOut->to_Hex( ) );
							$vOut = new Bit::Vector( 4096 );
							$vOut->Interval_Copy( $vrmd, 4096 - $vrmd->Size( ) + $j, $j, $vrmd->Size( ) - $j );
							$j = 4096 - $vrmd->Size( ) + $j;
						} else {
							$this->{Stream} .= pack( 'H*', $vOut->to_Hex( ) );
							$j = 4096;
						}
						$vOut->Interval_Copy( $vtmp, $j - $BitsPerCode, 0, $BitsPerCode );
						$j -= $BitsPerCode;
						if( $vtmp->to_Dec( ) == 256 ){	# Clear table code
							$BitsPerCode = 9;
							$Threshold = 257;
							$TableSize = 1;
							$vtmp->Resize( 9 );
						} elsif( $vtmp->to_Dec( ) == 257 ){	# Terminating code
							last OUTER;
						}
					}
					$vIn->Move_Right( $i );
					$vIn->Resize( $vIn->Size( ) - $i );
				} else {
					last;
				}
			}
		}
		my $right = $j - $j % 8;
		if( $j % 8 ){
			$vOut->Interval_Empty( $right, $right + $j % 8 );
		}
		if( $right ){
			$vOut->Move_Right( $right );
			$vOut->Resize( $vOut->Size( ) - $right );
		}
		$this->{Stream} .= pack( 'H*', $vOut->to_Hex( ) );
	} elsif( $this->{Mode} eq 'JPG' ){
		$this->{Stream} = $ImgData;
		substr( $ImgData, 0, 2 ) = '';		# Skip the 2-byte header
		my $Buffer;
		while( 1 ){
			my( $Dummy, $Marker, $Length ) = unpack( 'a an', substr( $ImgData, 0, 4, '' ) );
			$Buffer = substr( $ImgData, 0, $Length - 2, '' );
			last if( ord( $Marker ) > 0xBF && ord( $Marker ) < 0xD0 );
		}
		my @JPGInfo = unpack( 'CnnC*', $Buffer );
		$this->{Width} = $JPGInfo[2];
		$this->{Height} = $JPGInfo[1];
		$this->{BitsPerComponent} = $JPGInfo[0];
		if( $JPGInfo[3] == 3 ){		# Must be either 3 for true-color image, or 1 for grayscale image
			$this->{ColorSpace} = 'DeviceRGB';
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageC' );
		} else {
			$this->{ColorSpace} = 'DeviceGray';
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageG' );
		}
		$this->setFilter( 'DCTDecode', 'null' );
	} elsif( $this->{Mode} eq 'PNG' ){
		# At this stage, no filtering should be used for the image. The first byte for each scan line is removed here.
		my $PNGHeader = substr( $ImgData, 0, 8, '' );
		my $ChType = '';
		my %PNGChunks = ( );
		my $PNGData = '';
		while( $ChType ne 'IEND' ){
			my $ChLen = substr( $ImgData, 0, 4, '' );
			$ChType = substr( $ImgData, 0, 4, '' );
			$PNGChunks{$ChType} = substr( $ImgData, 0, unpack( 'N', $ChLen ), '' );
			my $CRC = substr( $ImgData, 0, 4, '' );
			if( $ChType eq 'IDAT' ){
				$PNGData .= $PNGChunks{IDAT};
			}
		}
		my @PNGInfo = unpack( 'NNC*', $PNGChunks{IHDR} );
		$this->{Width} = $PNGInfo[0];
		$this->{Height} = $PNGInfo[1];
		$this->{BitsPerComponent} = $PNGInfo[2];
		$PNGData = Compress::Zlib::uncompress( $PNGData );
		if( $PNGInfo[4] || $PNGInfo[5] || $PNGInfo[6] ){
			if( $PDF::root->{Prefs}->{SkipBadImage} ){
				return $this->setErrorImage( );
			} else {
				die "$File: PNG image with filtering, interlacing and non-Zlib/Deflate compression are not supported." 
			};
		}
		my $BytesPerLine = int( $this->{Width} * $this->{BitsPerComponent} * ( $PNGInfo[3] == 2? 3: 1 ) / 8 + 0.5 );
		while( length( $PNGData ) ){
			substr( $PNGData, 0, 1, '' );
			$this->{Stream} .= substr( $PNGData, 0, $BytesPerLine, '' );
		}
		$this->{Stream} = Compress::Zlib::compress( $this->{Stream} );
		$this->setFilter( 'FlateDecode', 'null' );
		if( !$PNGInfo[3] ){
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageG' );
			$this->{ColorSpace} = 'DeviceGray';
		} else {
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageC' );
			$this->{ColorSpace} = 'DeviceRGB';
		}
		if( $PNGInfo[3] & 1 ){
			$PNGChunks{PLTE} .= "\xFF" x ( 2 ** $this->{BitsPerComponent} * 3 - length( $PNGChunks{PLTE} ) );
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageI' );
			$this->{ColorTable} = new PDFStream( $PNGChunks{PLTE} );
		}
	} elsif( $this->{Mode} eq 'BMP' ){
		# BMP supports 1, 4, 8, 16, 24, 32-bit (1, 4, 8 with palete). Each scanline must ends at a DWORD boundary.
		# 16-bit: 1 word = 1+5+5+5 (unused+BGR) bits; 32-bit: 1 dword = 0+B+G+R bytes
		my $BMPHeader = substr( $ImgData, 0, 54, '' );
		my @BMPInfo = unpack( 'V*', substr( $BMPHeader, 2, 24 ) );
		$this->{Width} = $BMPInfo[-2];
		$this->{Height} = abs( $BMPInfo[-1] );	# Note: if this value is negative, the image is scanned top-down. This possibility is overlooked here.
		my $BMPCompress;
		( $this->{BitsPerComponent}, $BMPCompress ) = unpack( 'vV', substr( $BMPHeader, 0x1C, 6 ) );
		if( $BMPCompress ){
			if( $PDF::root->{Prefs}->{SkipBadImage} ){ return $this->setErrorImage( ); } else { die "$File: BMP Run-length compression not supported." };
		}
		if( $this->{BisPerComponent} == 16 ){
			if( $PDF::root->{Prefs}->{SkipBadImage} ){ return $this->setErrorImage( ); } else { die "$File: 16-bit BMP file format not supported." };
		}
		my $NumColors = 2 ** $this->{BitsPerComponent};
		my $TotalBits = $this->{BitsPerComponent} * $this->{Width};
		my $ScanLineLen = ( ( $TotalBits % 32 )? 4: 0 ) + int( $TotalBits / 32 ) * 4;
		my $StoreLineLen = ( ( $TotalBits % 8 )? 1: 0 ) + int( $TotalBits / 8 );
		if( $this->{BitsPerComponent} <= 8 ){
			my $BMPPalette = substr( $ImgData, 0, $NumColors * 4, '' );
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageI' );
			my $ColorTable = '';
			for( my $i=0; $i<length($BMPPalette)-1; $i+=4 ){
				$ColorTable .= reverse substr( $BMPPalette, $i, 3 );
			}
			$this->{ColorTable} = new PDFStream( $ColorTable );
		} else {
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageC' );
			$this->{ColorSpace} = 'DeviceRGB ';
		}
		my $BMPBuffer = '';
		if( $this->{BitsPerComponent} > 16 ){
			for( 1..$this->{Height} ){
				$BMPBuffer = substr( $ImgData, 0, $ScanLineLen, '' );
				if( $this->{BitsPerComponent} == 24 ){
					for( my $i=0; $i<length($BMPBuffer)-1; $i+=3 ){
						substr( $BMPBuffer, $i, 3 ) = reverse substr( $BMPBuffer, $i, 3 );
					}
					substr( $this->{Stream}, 0, 0, substr( $BMPBuffer, 0, $StoreLineLen ) );
				} else {
					my $Buffer = '';
					for( my $i=0; $i<length($BMPBuffer)-1; $i+=4 ){
						$Buffer .= reverse substr( $BMPBuffer, $i+1, 3 );
					}
					substr( $this->{Stream}, 0, 0, substr( $Buffer, 0, $StoreLineLen ) );
				}
			}
			$this->{BitsPerComponent} = 8;
		} elsif( $this->{BitsPerComponent} == 8 ){
			for( 1..$this->{Height} ){
				$BMPBuffer = substr( $ImgData, 0, $ScanLineLen, '' );
				substr( $this->{Stream}, 0, 0, substr( $BMPBuffer, 0, $this->{Width} ) );
			}
		} else {
			for( 1..$this->{Height} ){
				$BMPBuffer = unpack( 'B*', substr( $ImgData, 0, $ScanLineLen, '' ) );
				substr( $this->{Stream}, 0, 0, substr( $BMPBuffer, 0, $StoreLineLen * 8 ) );
			}
			$this->{Stream} =~ s/(.{8})/pack('B8',$1)/ge;
		}
		$this->{Stream} = Compress::Zlib::compress( $this->{Stream} );
		$this->setFilter( 'FlateDecode', 'null' );
	} elsif( $this->{Mode} eq 'TIF' ){
		my $TIFHeader = substr( $ImgData, 0, 8 );
		my $PC = ( $TIFHeader =~ m{^II} );
		my( $IFDOffset, $IFDNumber, $EntryBuffer, %TIFTags );
		$IFDOffset = unpack( $PC? 'V': 'N', substr( $TIFHeader, 4, 4 ) );
		my @ValueTypes = ( 0, 1, 1, 2, 4, 8 );
		my @ValuePats  = ( '', 'C', 'a', $PC? 'v': 'n', $PC? 'V': 'N', $PC? 'VV': 'NN' );
		while( $IFDOffset ){
			$IFDNumber = unpack( $PC? 'v': 'n', substr( $ImgData, $IFDOffset, 2 ) );
			$IFDOffset += 2;
			for ( 1..$IFDNumber ){
				$EntryBuffer = substr( $ImgData, $IFDOffset, 12 );
				$IFDOffset += 12;
				my @ThisEntry = unpack( $PC? 'vvV': 'nnN', $EntryBuffer );
				next if( $ThisEntry[0] > 32767 );
				my @EntryValues = ( );
				if( $ValueTypes[ $ThisEntry[1] ] * $ThisEntry[2] <= 4 ){
					@EntryValues = unpack( $ValuePats[ $ThisEntry[1] ] x $ThisEntry[2], substr( $EntryBuffer, -4 ) );
				} else {
					my $ValOffset = unpack( $PC? 'V': 'N', substr( $EntryBuffer, -4 ) );
					@EntryValues = unpack( $ValuePats[ $ThisEntry[1] ] x $ThisEntry[2], substr( $ImgData, $ValOffset, $ValueTypes[ $ThisEntry[1] ] * $ThisEntry[2] ) );
				}
				push( @ThisEntry, \@EntryValues );
				$TIFTags{ $TIFTagTranslate{ $ThisEntry[0] } } = \@ThisEntry;;
			}
			$EntryBuffer = substr( $ImgData, $IFDOffset, 4 );
			$IFDOffset = unpack( $PC? 'V': 'N', $EntryBuffer );
		}
		$this->{Width} = $TIFTags{ImageWidth}->[3]->[0];
		$this->{Height} = $TIFTags{ImageLength}->[3]->[0];
		$this->{BitsPerComponent} = $TIFTags{BitsPerSample}->[3]->[0];
		for( 1 .. $TIFTags{StripByteCounts}->[2] ){
			$this->{Stream} .= substr( $ImgData, $TIFTags{StripOffsets}->[3]->[$_-1], $TIFTags{StripByteCounts}->[3]->[$_-1] );
		}
		if( $TIFTags{Compression}->[3]->[0] != 1 ){		# Compression used.
			if( $PDF::root->{Prefs}->{SkipBadImage} ){ return $this->setErrorImage( ); } else { die "$File: Compressed TIFF files are not supported." };
		} else {
			$this->{Stream} = Compress::Zlib::compress( $this->{Stream} );
			$this->setFilter( 'FlateDecode', 'null' );
		}
		if( $TIFTags{PhotometricInterpretation}->[3]->[0] <= 1 ){		# bitmap (B&W) or grayscale image
			if( $TIFTags{BitsPerSample}->[3]->[0] == 1 ){
				my @colors = ( "\xFF\xFF\xFF", "\x00\x00\x00" );
				if( $TIFTags{PhotometricInterpretation}->[3]->[0] ){
					@colors = reverse @colors;
				}
				$this->{ColorSpace} = new PDFStream( join( '', @colors ) );
				$PDF::root->getPagesRoot( )->setProcSet( 'ImageI' );
			} else {
				$PDF::root->getPagesRoot( )->setProcSet( 'ImageG' );
				$this->{ColorSpace} = 'DeviceGray';
			}
		} elsif( $TIFTags{PhotometricInterpretation}->[3]->[0] == 2 ){	# True color image
			$this->{ColorSpace} = 'DeviceRGB';
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageC' );
		} elsif( $TIFTags{PhotometricInterpretation}->[3]->[0] == 3 ){	# Palette color image
			my $Bytes = $TIFTags{ColorMap}->[2] / 3;
			my $TIFPalette = join( '', map{ pack( 'C3', int( $TIFTags{ColorMap}->[3]->[$_-1] / 256 ), int( $TIFTags{ColorMap}->[3]->[$_+$Bytes-1] / 256 ), int( $TIFTags{ColorMap}->[3]->[$_+2*$Bytes-1] / 256 ) ) } 1 .. $Bytes );
			$this->{ColorTable} = new PDFStream( $TIFPalette );
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageC', 'ImageI' );
		} elsif( $TIFTags{PhotometricInterpretation}->[3]->[0] == 5 ){	# CMYK color image
			$this->{ColorSpace} = 'DeviceCMYK';
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageC' );
		}
	} elsif( $this->{Mode} eq 'TGA' ){
		my @TGAInfo = unpack( 'C3v2Cv4C2', substr( $ImgData, 0, 18, '' ) );
		$this->{Width} = $TGAInfo[8];
		$this->{Height} = $TGAInfo[9];
		if( $TGAInfo[-2] == 16 || $TGAInfo[-2] == 32 ){
			if( $PDF::root->{Prefs}->{SkipBadImage} ){ return $this->setErrorImage( ); } else { die "$File: Alpha channel not supported for TGA images." };
		}
		my $ScanLineLen = $this->{Width} * $TGAInfo[-2] / 8;
		if( ( $this->{BitsPerComponent} = $TGAInfo[-2] ) == 24 ){
			$this->{BitsPerComponent} = 8;
		}
		substr( $ImgData, 0, $TGAInfo[0], '' );		# Skip image ID, if present
		if( $TGAInfo[2] % 8 == 3 ){					# Grayscale image
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageG' );
			$this->{ColorSpace} = 'DeviceGray ';
		} elsif( $TGAInfo[2] % 8 == 2 ){			# 24-bit image
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageC' );
			$this->{ColorSpace} = 'DeviceRGB ';
		} elsif( $TGAInfo[2] % 8 == 1 ){			# 256-color image
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageC', 'ImageI' );
			my $ColorTable = substr( $ImgData, 0, $TGAInfo[4] * 3, '' );
			for( my $i=0; $i<length($ColorTable)-1; $i+=3 ){
				substr( $ColorTable, $i, 3 ) = reverse substr( $ColorTable, $i, 3 );
			}
			$this->{ColorTable} = new PDFStream( $ColorTable );
		}
		for( 1..$this->{Height} ){
			my( $v, $Buffer ) = ( );
			if( $TGAInfo[2] > 8 ){
				while( length( $Buffer ) < $ScanLineLen ){
					$v = unpack( 'C', substr( $ImgData, 0, 1, '' ) );
					if( $v > 0x80 ){
						$Buffer .= ( substr( $ImgData, 0, $TGAInfo[-2] / 8, '' ) x ( $v - 0x80 + 1 ) );
					} else {
						$Buffer .= substr( $ImgData, 0, $TGAInfo[-2] / 8 * ( $v + 1 ), '' );
					}
				}
			} else {
				$Buffer = substr( $ImgData, 0, $ScanLineLen, '' );
			}
			if( ( $TGAInfo[-1] >> 4 ) % 2 ){		# If pixels are stored from right to left, just reverse the sequence
				$Buffer = reverse $Buffer;
			} elsif( $TGAInfo[2] % 8 == 2 ){		# Otherwise, reverse BGR triples to RGB
				for( my $i=0; $i<length($Buffer)-1; $i+=3 ){
					substr( $Buffer, $i, 3 ) = reverse substr( $Buffer, $i, 3 );
				}
			}
			if( ( $TGAInfo[-1] >> 5 ) % 2 ){		# If lines are stored from top to bottoms, append to stream
				$this->{Stream} .= $Buffer;
			} else {								# Otherwise, insert in front of the stream
				substr( $this->{Stream}, 0, 0, $Buffer );
			}
		}
		$this->{Stream} = Compress::Zlib::compress( $this->{Stream} );
		$this->setFilter( 'FlateDecode', 'null' );
	} elsif( $this->{Mode} eq 'PCX' ){
		my @PCXInfo = unpack( 'C4v6a48C2v4', substr( $ImgData, 0, 128, '' ) );
		$this->{Width} = $PCXInfo[6] - $PCXInfo[4] + 1;
		$this->{Height} = $PCXInfo[7] - $PCXInfo[5] + 1;
		$this->{BitsPerComponent} = $PCXInfo[3];
		if( $PCXInfo[1] == 5 && $PCXInfo[-5] >= 3 ){	# 24-bit color, 3 or 4 planes (RGBI)
			$this->{ColorSpace} = 'DeviceRGB ';
			$PDF::root->getPagesRoot( )->setProcSet( 'ImageC' );
		} elsif( $PCXInfo[-5] == 1 ){	# One plane only
			if( $PCXInfo[3] == 8 ){		# 256 Color, palette appended to file end, preceded by "\x0C"
				my $Palette = substr( $ImgData, -769 );
				if( substr( $Palette, 0, 1, '' ) eq "\x0C" ){
					$this->{ColorTable} = new PDFStream( $Palette );
					$PDF::root->getPagesRoot( )->setProcSet( 'ImageC', 'ImageI' );
				}
			} elsif( $PCXInfo[3] == 1 ){	# black & white
				$this->{ColorSpace} = 'DeviceGray ';
				$PDF::root->getPagesRoot( )->setProcSet( 'ImageG' );
			}
		}
		my( $c, $v, $c2 );
		for( 1..$this->{Height} ){
			my $Buffer = '';
			my $ByteCount = $PCXInfo[-5] * $PCXInfo[-4];
			while( 1 ){
				$c = substr( $ImgData, 0, 1, '' );
				$v = unpack( 'C', $c );
				if( $v >= 0xC0 ){
					$c2 = substr( $ImgData, 0, 1, '' );
					$Buffer .= $c2 x ( $v - 0xC0 );
					$ByteCount -= ( $v - 0xC0 );
				} else {
					$Buffer .= $c;
					$ByteCount--;
				}
				last if( !$ByteCount );
			}
			if( $PCXInfo[1] == 5 && $PCXInfo[-5] >= 3 ){	# 24-bit color
				my @Planes = ( );
				for( 1..$PCXInfo[-5] ){
					push( @Planes, substr( $Buffer, 0, $PCXInfo[-4], '' ) );
				}
				for( 1..$this->{Width} ){
					$this->{Stream} .= substr( $Planes[0], 0, 1, '' ) . substr( $Planes[1], 0, 1, '' ) . substr( $Planes[2], 0, 1, '' );
				}
			} elsif( $PCXInfo[3] == 8 ){	# 256 color
				if( $this->{Width} % 2 ){
					substr( $Buffer, -1, 1, '' );
				}
				$this->{Stream} .= $Buffer;
			} elsif( $PCXInfo[3] == 1 ){	# black & white
				$this->{Stream} .= $Buffer;
			}
		}
		$this->{Stream} = Compress::Zlib::compress( $this->{Stream} );
		$this->setFilter( 'FlateDecode', 'null' );
	} elsif( $this->{Mode} eq 'EXIF' ){
		$this->{Stream} = $ImgData;
		my $ExifAppLen = unpack( 'v', substr( $ImgData, 4, 2 ) );
		my $ExifApp = substr( $ImgData, 12, $ExifAppLen );
		my $PC = ( $ExifApp =~ m{^II} );
		my( $IFDOffset, $IFDNumber, $EntryBuffer, %TIFTags );
		$IFDOffset = unpack( $PC? 'V': 'N', substr( $ExifApp, 4, 4 ) );
		my @ValueTypes = ( 0, 1, 1, 2, 4, 8 );
		my @ValuePats  = ( '', 'C', 'a', $PC? 'v': 'n', $PC? 'V': 'N', $PC? 'VV': 'NN' );
		my $ExifIFDParsed = 0;
		while( 1 ){
			while( $IFDOffset ){
				$IFDNumber = unpack( $PC? 'v': 'n', substr( $ExifApp, $IFDOffset, 2 ) );
				$IFDOffset += 2;
				for ( 1..$IFDNumber ){
					$EntryBuffer = substr( $ExifApp, $IFDOffset, 12 );
					$IFDOffset += 12;
					my @ThisEntry = unpack( $PC? 'vvV': 'nnN', $EntryBuffer );
					my @EntryValues = ( );
					if( $ValueTypes[ $ThisEntry[1] ] * $ThisEntry[2] <= 4 ){
						@EntryValues = unpack( $ValuePats[ $ThisEntry[1] ] x $ThisEntry[2], substr( $EntryBuffer, -4 ) );
					} else {
						my $ValOffset = unpack( $PC? 'V': 'N', substr( $EntryBuffer, -4 ) );
						@EntryValues = unpack( $ValuePats[ $ThisEntry[1] ] x $ThisEntry[2], substr( $ExifApp, $ValOffset, $ValueTypes[ $ThisEntry[1] ] * $ThisEntry[2] ) );
					}
					push( @ThisEntry, \@EntryValues );
					$TIFTags{ $TIFTagTranslate{ $ThisEntry[0] } } = \@ThisEntry;
				}
				$EntryBuffer = substr( $ExifApp, $IFDOffset, 4 );
				$IFDOffset = unpack( $PC? 'V': 'N', $EntryBuffer );
			}
			if( defined $TIFTags{ExifIFD} && !$ExifIFDParsed ){
				$ExifIFDParsed = 1;
				$IFDOffset = $TIFTags{ExifIFD}->[3]->[0];
				next;
			}
			last;
		}
		$this->{Width} = $TIFTags{PixelXDimension}->[3]->[0];
		$this->{Height} = $TIFTags{PixelYDimension}->[3]->[0];
		$this->{BitsPerComponent} = 8;
		$this->{ColorSpace} = 'DeviceRGB';
		$this->setFilter( 'DCTDecode', 'null' );
		$PDF::root->getPagesRoot( )->setProcSet( 'ImageC' );
	} else {
		if( $PDF::root->{Prefs}->{SkipBadImage} ){ return $this->setErrorImage( ); } else { die "Unknown image file format." };
	}
	$this->{DisplayWidth} ||= $this->{Width};
	$this->{DisplayHeight} ||= $this->{Height};
	$this->{FileHandle} = $PDFDoc::FileHandle;
	$this->setDiskBased( );
#	if( $this->{ColorTable} ){
#		$this->appendChild( $this->{ColorTable} );
#	}
	$PDF::root->getPagesRoot( )->appendImage( $this ) unless( $attr->{Inline} );
	return $this;
}

sub setErrorImage {
	my $this = shift;
	# The following two lines build an image showing red cross with a red border. It has a palette of two elements: red and white. Each pixel is represented by 1 bit.
	my @tmp = ( "\x8F\xFF\xF8", "\x87\xFF\xF0", "\x83\xFF\xE0", "\xC1\xFF\xC1", "\xE0\xFF\x83", "\xF0\x7F\x07", "\xF8\x3E\x0F", "\xFC\x1C\x1F", "\xFE\x08\x3F", "\xFF\x00\x7F", "\xFF\x80\xFF" );
	$this->{Stream} = join( '', "\x00" x 10, "\x3F\xFF\xFF\xFF\xFC" x 7, ( map { "\x3F$_\xFC" } ( @tmp, "\xFF\xC1\xFF", reverse @tmp ) ), "\x3F\xFF\xFF\xFF\xFC" x 6, "\x00" x 10 );
	$this->{Width} = $this->{Height} = 40;
	$this->{DisplayWidth} ||= $this->{Width};
	$this->{DisplayHeight} ||= $this->{Height};
	$this->{BitsPerComponent} = 1;
	$this->{ColorTable} = new PDFStream( "\xFF\x00\x00\xFF\xFF\xFF" );
	$PDF::root->getPagesRoot( )->setProcSet( 'ImageI' );
	$PDF::root->getPagesRoot( )->appendImage( $this ) unless( $this->{Inline} );
	return $this;
}

sub scaleBy {
	my( $this, $ratio ) = @_;
	push( @{$this->{XML}}, qq{<Scale Ratio="$ratio" />} );
	$this->{DisplayWidth} *= $ratio;
	$this->{DisplayHeight} *= $ratio;
}

sub scaleTo {
	my( $this, $newWidth, $newHeight ) = @_;
	push( @{$this->{XML}}, qq{<Scale Width="$newWidth" Height="$newHeight" />} );
	$this->{DisplayWidth} = &PDF::tellSize( $newWidth );
	$this->{DisplayHeight} = &PDF::tellSize( $newHeight );
}

sub setAsMask {
	my $this = shift;
	if( $this->{BitsPerComponent} != 1 ){
		if( $PDF::root->{Prefs}->{SkipBadImage} ){ return $this->setErrorImage( ); } else { die "SetAsMask: This image can not be set as a mask because the bits-per-component is not 1. Only bi-level images can be used." };
	} else {
		$this->{IsMask} = 1;
	}
}

sub setMask {
	# When specifying a color as mask, $param is the tolerance. Otherwise $param is disregarded.
	my( $this, $mask, $param ) = @_;
	if( ref( $mask ) eq 'ImageContent' ){	# Explicit masking (use a 1-bit image as the stencil mask)
		$this->{Mask} = $mask;
		$mask->scaleTo( $this->{Width}, $this->{Height} );
		$mask->setAsMask( );
		push( @{$this->{XML}}, qq{<Mask Image="$mask->{Name}" />} );
	} else {								# Color key masking
		foreach my $c ( &Color::tellColor( $mask ) ){
			$c = int( $c * 255 );
			push( @{$this->{MaskDecode}}, &PDF::max( 0, $c - $param ) );
			push( @{$this->{MaskDecode}}, &PDF::min( 255, $c + $param ) );
		}
		push( @{$this->{XML}}, qq{<Mask Color="$mask" Range="$param" />} );
	}
}

sub adjustColors {
	# Linear interplotation: two params both in the range 0 to 1
	my( $this, @x ) = @_;
	push( @{$this->{Decode}}, @x );
}

sub invert {
	my $this = shift;
	if( !$this->{ColorSpace} ){
		$this->{ColorTable}->{Stream} =~ s/(.)/chr(255-ord($1))/ge;
	} else {
		my $t = [ 0, 1, 0, 0, 2, 0, 0, 0, 3  ]->[ $this->{BitsPerComponent} ];
		$this->adjustColors( ( 1, 0 ) x $t );
	}
	push( @{$this->{XML}}, qq{<Exec Cmd="Invert" />} );
}

sub lighten {
	my( $this, $ratio ) = @_;
	my @v = ( 0, 1 );
	if( $ratio < 0 ){
		$v[1] += $ratio;
	} else {
		$v[0] += $ratio;
	}
	return if( !$this->{ColorSpace} );
	my $t = [ 0, 1, 0, 0, 2, 0, 0, 0, 3  ]->[ $this->{BitsPerComponent} ];
	$this->adjustColors( ( @v ) x $t );
	push( @{$this->{XML}}, qq{<Exec Cmd="Lighten" Ratio="$ratio" />} );
}

#  Image content are normally compressed already, so UseCompress has not effect here.
sub makeInlineCode {
	my $this = shift;
	my $space;
	if( $this->{ColorTable} ){	# Indexed
		$space = sprintf( "/CS [ /Indexed /DeviceRGB %d <%s> ] ", 2 ** $this->{BitsPerComponent} - 1, unpack( 'H*', $this->{ColorTable}->{Stream} ) );
	} else {
		$space = "/CS /$this->{ColorSpace} ";
	}
	my $code = join( $PDF::endln,
		'BI',
		qq{/W $this->{Width} },
		qq{/H $this->{Height} },
		qq{/BPC $this->{BitsPerComponent} },
		$space,
		qq{/F [ } . join( ' ', map { '/'.$_ } @{$this->{Filters}} ) . ' ] ',
		qq{/DP [ } . join( ' ', @{$this->{DecodeParms}} ) . ' ] ',
	);
	if( @{$this->{Decode}} ){
		$code .= qq{$PDF::endln/D [} . join( ' ', @{$this->{Decode}} ) . ']';
	}
	$code .= join( "\x0D",	# Must be "\x0D" -- or the viewer may have trouble with the image data.
		'',
		'ID',
		'',
	);
	if( $this->{DiskBased} ){
		my $data;
		seek( $this->{FileHandle}, $this->{StreamStart}, SEEK_SET );
		read( $this->{FileHandle}, $data, $this->{StreamLength} );
		$code .= $data;
	} else {
		$code .= $this->{Stream};
	}
	$code .= join( "\x0D",
		'',
		'EI',
		'',
	);
	return $code;
}

sub getWidth {
	my $this = shift;
	return ( $this->{DisplayWidth} || $this->{Width} );
}

sub getHeight {
	my $this = shift;
	return ( $this->{DisplayHeight} || $this->{Height} );
}

sub customCode {
	my $this = shift;
	# The name of the image is no longer exported because of a same resource can
	# be referred by different names and Acrobat actually ignores this entry.
	print join( $PDF::endln,
		'',
		'/Type /XObject ',
		'/Subtype /Image ',
		qq{/Width $this->{Width} },
		qq{/Height $this->{Height} },
		qq{/BitsPerComponent $this->{BitsPerComponent} },
	);
	if( @{$this->{Decode}} ){
		print qq{$PDF::endln/Decode [} . join( ' ', @{$this->{Decode}} ) . ']';
	}
	if( $this->{IsMask} ){
		print qq{$PDF::endln/ImageMask true};
	} else {
		if( $this->{ColorTable} ){
			printf(
				"$PDF::endln/ColorSpace [ /Indexed /DeviceRGB %d <%s> ] ",
				2 ** $this->{BitsPerComponent} - 1,
#				"$this->{ColorTable}->{ObjId} 0 R",
				unpack( 'H*', $PDF::root->{Encrypt}? &PDF::RC4( $this->{EncKey}, $this->{ColorTable}->{Stream} ): $this->{ColorTable}->{Stream} )
			);
		} else {
			print qq{$PDF::endln/ColorSpace /$this->{ColorSpace}};
		}
		if( $this->{Mask} ){
			print qq{$PDF::endln/Mask $this->{Mask}->{ObjId} 0 R};
		} elsif( @{$this->{MaskDecode}} ){
			print qq{$PDF::endln/Mask [} . join( ' ', @{$this->{MaskDecode}} ) . ']';
		}
	}
}

sub startXML {
	my( $this, $dep ) = @_;
	return if( ref( $this->{File} ) eq 'PDFStream' );
	print "\t" x $dep, '<Image Width="', $this->{DisplayWidth}, '" Height="', $this->{DisplayHeight}, '"';
	for( qw(File Name) ){
		next unless( $this->{$_} );
		print qq{ $_="} . &PDF::escXMLChar( $this->{$_} ) .'"';
	}
	if( @{$this->{XML}} ){
		print ">\n";
		for( @{$this->{XML}} ){
			print "\t" x ( $dep + 1 ), $_, "\n";
		}
	} else {
		print "/>\n";
	}
}

sub endXML {
	my( $this, $dep ) = @_;
	return if( !@{$this->{XML}} || ref( $this->{File} ) eq 'PDFStream' );
	print "\t" x $dep, "</Image>\n";
}

sub newFromXML {
	my( $class, $xml ) = @_;
	bless $xml, 'HASH';
	my $this = new ImageContent( $xml->{File}, $xml->{Width}, $xml->{Height}, { 'Name'=>$xml->{Name} } );
	foreach my $kid ( @{$xml->{Kids}} ){
	my $cmd = ref( $kid );
		$cmd =~ s/^(\w+::)+//;	# Reveal bare tag names
		next if( $cmd eq 'Characters' );
		bless $kid, 'HASH';
		if( $cmd eq 'Scale' ){
			if( $kid->{Ratio} ){
				$this->scaleBy( $kid->{Ratio} );
			} else {
				$this->scaleTo( $kid->{Width}, $kid->{Height} );
			}
		} elsif( $cmd eq 'Mask' ){
			if( $kid->{Image} ){
				$this->setMask( &PDF::getObjByName( $kid->{Image} ) ); # Typo $kid->{Mask} corrected 01/06/2003
			} else {
				$this->setMask( $kid->{Color}, $kid->{Range} );
			}
		} elsif( $cmd eq 'Exec' ){
			if( $kid->{Cmd} eq 'Invert' ){
				$this->invert( );
			} elsif( $kid->{Cmd} eq 'Lighten' ){
				$this->lighten( $kid->{Ratio} );
			}
		}
	}
	return $this;
}

sub finalize {
	my $this = shift;
	$this->SUPER::finalize( );
	for( qw(XML MaskDecode Decode) ){
		@{$this->{$_}} = ( );
	}
	undef $this->{ColorTable} if( exists $this->{ColorTable} );
}

1;