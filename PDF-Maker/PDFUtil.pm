#===========================================================================#
#     PDFeverywhere 3.0  (c) 2001 Zhigang (Jeoy) Li / PDFeverywhere.com     #
#===========================================================================#
# Defines certain constant variables and subroutines.
# Specifications:
# <<generic>>
#	min( nums[]: float ): float
#	max( nums[]: float ): float
#	tellTime( ): String {PDF format}
#	tellSize( size: String ): float
# <<error handling>>
#	PDFError( class: String,  message: String ) {dies}
#	redirectSTDERR( filename: String ) {created in temp dir}
#	restoreSTDERR( filename: String )
#	secureFileName( filename: String ): String
# <<string manipulation>>
#	encodeA85( data: String )
#	escStr( strs[]: String ): Array or String
#	hexToStr( str: String ): String
#	strToHex( str: String ): String
#	strToName( str: String ): String
# <<encryption>>
#	To32( n: int ): int
#	padPwd( pwd: String ): String {32 bytes}
#	MD5( inputs[]: string ): String {16 bytes}
#	RC4( key: String, data: String ): String

package PDF;
use File::Basename;

use Time::Local;

$PDF::endln = "\x0D\x0A";	# No "\n" and "\r" are used throughout the library.
$PDF::TempDir = '/usr/local/www/hs_utils/data';

# Unit conversion table
%PDF::SizeToPoint = (
	in => 72,			# Inch
	mm => 2.8346,		# Millimeter
	cm => 28.346,		# Centimeter
	pt => 1,			# Point
	px => 1,			# Pixel
);
# Used when reading characters from PDF char-string
%PDF::UnescapeChars = (
	n => "\n", r => "\r", t => "\t", b => "\b", f => "\f", ')' => ')', '(' => '(', '\\' => '\\',
);
# Used when applying security setting
$PDF::PadChars = "\x28\xBF\x4E\x5E\x4E\x75\x8A\x41\x64\x00\x4E\x56\xFF\xFA\x01\x08\x2E\x2E\x00\xB6\xD0\x68\x3E\x80\x2F\x0C\xA9\xFE\x64\x53\x69\x7A";

sub escXMLChar {
	my $str = shift;
	if( !defined $str ){
		$str = '';
	}
	$str =~ s/&/&amp;/g;
	$str =~ s/"/&quot;/g;
	$str =~ s/</&lt;/g;
	$str =~ s/\x0D?\x0A/&#xA;/g;
	$str =~ s/([\x80-\xFF])/join( '', '&#x', uc(unpack('H*',$1))).';'/ge;
=dev
	$str =~ s/([\x80-\xFF])/
		chr( $1 ) le "\xBF"? ( "\xC2" . $1 ): ( "\xC3" . chr( ord($1) - 64 ) )
	/gex;
=cut
	return $str;
}

# Returns the minimum value in a list
sub min {
	my @nums = sort { $a <=> $b } @_;
	return $nums[0];
}

# Returns the maximum value in a list
sub max {
	my @nums = sort { $b <=> $a } @_;
	return $nums[0];
}

# Return current time in PDF syntax.
sub tellTime {
	my $CurrTime = time;
	my @tvals = localtime( $CurrTime );
	my $Zone = ( Time::Local::timegm( @tvals ) - $CurrTime ) / 3600;
	@tvals = reverse @tvals;
	$tvals[3] += 1900;
	$tvals[4]++;
	return sprintf( "D:%4d%02d%02d%02d%02d%02d%s%02d'%02d'",
		@tvals[3..8],						# Year, month, day, hour, min, sec
		[ 'Z','+','-' ]->[ $Zone <=> 0 ],	# Time zone prefix (one char)
		abs( int( $Zone ) ),				# Time zone
		int( abs( $Zone ) * 60 % 60 )		# Time zone's minute offset
	);
}

# Returns the value in point for a literal. Caller need to convert to "%.4f".
sub tellSize {
	my $size = shift;
	return 0 if( !defined $size );
	$size =~ /^([+-]?[\d\.]+)\s*(\w*)$/;
	my( $num, $postfix ) = ( $1, lc($2) );
	return 0 if( !defined $num );
	if( !defined $postfix || !defined $PDF::SizeToPoint{$postfix} ){
		return sprintf( "%.4f", $num * 1 ) + 0;
	} else {
		return sprintf( "%.4f", $PDF::SizeToPoint{$postfix} * $num ) + 0;
	}
}

#===========================================================================#
#  Error handling - Please revise for your own use. They are deprecated!
#===========================================================================#

sub PDFError {
	my( $class, $msg ) = @_;
	die "$class: $msg";
}

# The following three functions are used for debugging purpose only.

# Redirects STDERR into a file, which must be supplied.
sub redirectSTDERR {
	my $file = secureFileName( shift );
	open( OLDERR, ">&STDERR" );
	open( STDERR, ">$PDF::TempDir/$file" );
	select( STDERR );
}

# Restore STDERR
sub restoreSTDERR {
	close( STDERR );
	open( STDERR, ">&OLDERR" );
}

# Ensures a file name doesn't contain pipes and spaces.
sub secureFileName {
	my $file = shift;
	$file =~ s/[\|<>\*\?]//g;
	return $file;
}

#===========================================================================#
#  String data manipulation
#===========================================================================#

# Apply ASCII85 filter to a data stream.
sub encodeA85 {
	my $data = shift;
	$$data =~ s{(.)(.)(.)(.)|(.)(.)(.)|(.)(.)|(.)}{
		my $b = ( ord($1) << 24 ) + ( ord($2 or 0) << 16 ) +
			( ord($3 or 0) << 8 ) + ord($4 or 0);
		my $c = '';
		!$b && length($&) == 4?
			( $c .= '!!!!!' ):
			( map{ $c .= chr( $b / 85**$_ + 33 ); $b %= 85**$_; }
				reverse ( 0..4 ) );
		substr( $c, 0, length($&)+1 );
	}sgex;
	$$data .= '~>';
	$$data =~ s/(.{64})/$1$PDF::endln/g;
}

# Make an integer 32-bit only
sub To32 {
	my $n = shift;
	# "$n & 0xFFFFFFFF" just doesn't always work!!
	return $n - int( $n / 4294967296 ) * 4294967296;
}

sub MD5_1 { my( $x, $y, $z ) = @_; return &To32( $x & $y ) | &To32( ~$x & $z ); }
sub MD5_2 { my( $x, $y, $z ) = @_; return &To32( $x & $z ) | &To32( $y & ~$z ); }
sub MD5_3 { my( $x, $y, $z ) = @_; return &To32( $x ^ $y ^ $z ); }
sub MD5_4 { my( $x, $y, $z ) = @_; return &To32( $y ^ ( $x | ~$z ) ); }
sub MD5_R {
	my( $x, $n ) = @_;
	#	The << operation doesn't work reliably so we have to use multiplication.
	return &To32( $x * ( 2 ** $n ) ) | ( &To32( $x ) >> ( 32 - $n ) );
}
@MD5_T = map{ int( 4294967296 * abs( sin( $_ ) ) ) } 1..64;

# MD5 digest method
sub MD5 {
	my @inputs = @_;
	for( @inputs ){ $_ ||= ''; }
	my $msg = join( '', @inputs );
	my $msglen = length( $msg );
	my $padlen = 56 - ( $msglen + 1 ) % 64;
	if( $padlen < 0 ){
		$padlen += 64;
	}
	$msg .= chr( 0x80 ) . ( chr( 0 ) x $padlen );
	$msg .= pack( 'V*', ( $msglen << 3 ) & 0xFFFFFFFF, $msglen >> 29 );
	my @M = unpack( 'V*', $msg );
	my ( $A, $B, $C, $D ) = ( 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476 );
	my @subs = ( \&MD5_1, \&MD5_2, \&MD5_3, \&MD5_4 );
	my @pk = ( 0..15, 1, 6, 11, 0, 5, 10, 15, 4, 9, 14, 3, 8, 13, 2, 7, 12, 5, 8, 11, 14, 1, 4, 7, 10, 13, 0, 3, 6, 9, 12, 15, 2, 0, 7, 14, 5, 12, 3, 10, 1, 8, 15, 6, 13, 4, 11, 2, 9 );
	my @ps = ( 7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21 );
	my @refs = ( \$A, \$B, \$C, \$D );
	while( scalar @M ){
		my $i = 0;
		my ( $AA, $BB, $CC, $DD ) = ( $A, $B, $C, $D );
		for $i ( 0..63 ){
			my( $a, $b, $c, $d ) = @refs;
			my $f = $subs[ int( $i / 16 ) ];
			$$a = &To32( $$b + &MD5_R( $$a + &$f( $$b, $$c, $$d ) + $M[ $pk[ $i ] ] + $MD5_T[ $i ], $ps[ $i % 4 + int( $i / 16 ) * 4 ] ) );
			unshift( @refs, pop @refs );
		}
		$A = &To32( $A + $AA ); $B = &To32( $B + $BB ); $C = &To32( $C + $CC ); $D = &To32( $D + $DD );
		splice( @M, 0, 16 );
	}
	return pack( 'V*', &To32($A), &To32($B), &To32($C), &To32($D) );
}

# Arc-four encryption method
sub RC4 {
	my @k = unpack( 'C*', shift );	# Key
	my $str = shift || '';
	my @s = 0..255;		# State
	my( $i, $j, $encr ) = ( 0, 0, '' );
	for $i ( 0..255 ){
		$j = ( $k[ $i % ( scalar @k ) ] + $s[ $i ] + $j ) % 256;
		@s[ $i, $j ] = @s[ $j, $i ];
	}
	$i = $j = 0;
	foreach( unpack( 'C*', $str ) ){
		++$i;
		$i %= 256;
		$j = ( $s[ $i ] + $j ) % 256;
		@s[ $i, $j ] = @s[ $j, $i ];
		$encr .= pack( 'C', $_ ^ $s[ ( $s[$i] + $s[$j] ) % 256 ] );
	}
	return $encr;
}

# Escape special characters in PDF string. Requires one or more string literals and return the escaped strings in the same order.
sub escStr {
	my @strs = @_;
	foreach ( @strs ){
		if( !defined $_ ){ $_= ''; }	# $_ could be a literal '0'
		s/([\\\(\)])/\\$1/g;
		s/\x0A/\\n/g;
		s/\x0D/\\r/g;
	}
	return wantarray? @strs: $strs[0];
}

# Convert a hex string to its binary form
sub hexToStr {
	my $str = shift;
	$str =~ s/[^a-fA-F0-9]//g;
	$str =~ s/(..)/pack( "c", hex($1) )/ge;
	return $str;
}

# Convert a binary string to its hex form
sub strToHex {
	return '<' . unpack( 'H*', shift ) . '>';
}

# Convert a string to a PDF name object by escaping all non-word chars.
sub strToName {
	my $name = shift;
	$name =~ s/(\W)/'#'.unpack( 'H*', $1 )/ge;
	return $name;
}

sub padPwd {
	my $pwd = shift;
	if( !defined $pwd ){
		$pwd = '';
	}
	my $len = length( $pwd );
	if( $len > 32 ){
		substr( $pwd, 32 ) = '';
	} else {
		$pwd .= substr( $PDF::PadChars, 0, 32 - $len );
	}
	return $pwd;
}

1;
