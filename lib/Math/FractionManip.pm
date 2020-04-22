package Math::FractionManip;

# ABSTRACT: Manipulate fractions

use strict;
#use warnings;

our $VERSION = '0.5401';

use Carp;
use Math::BigInt;
use Math::BigFloat;
use overload
  '+'      => 'add',
  '-'      => 'sub',
  '*'      => 'mul',
  '/'      => 'div',
  'abs'    => 'abs',
  '**'     => 'pow',
  'sqrt'   => 'sqrt',
  '<=>'    => 'cmp',
  '""'     => 'string',
  '0+'     => 'decimal',
  fallback => 1;

my %DEF = (
  CURRENT => { TAGS => [qw/ NORMAL REDUCE SMALL AUTO /], DIGITS => undef, SYSTEM => 1, NAME => 'DEFAULT' },
  DEFAULT => { TAGS => [qw/ NORMAL REDUCE SMALL AUTO /], DIGITS => undef, READONLY => 1, SYSTEM => 1 },
  BLANK   => { TAGS => ['', '', ''], DIGITS => '', READONLY => 1, SYSTEM => 1 },
);

my ($OUTFORMAT, $REDUCE, $SIZE, $AUTO, $INTERNAL, $RED_STATE) = (0 .. 5);
my $TAG_END = 3;    #Last index of tags meant to be kept.

my %TAGS = (
  NORMAL     => [$OUTFORMAT, 'NORMAL'],
  MIXED      => [$OUTFORMAT, 'MIXED'],
  MIXED_RAW  => [$OUTFORMAT, 'MIXED_RAW'],
  RAW        => [$OUTFORMAT, 'RAW'],
  DEF_MIXED  => [$OUTFORMAT, undef],
  REDUCE     => [$REDUCE,    'REDUCE'],
  NO_REDUCE  => [$REDUCE,    'NO_REDUCE'],
  DEF_REDUCE => [$REDUCE,    undef],
  SMALL      => [$SIZE,      'SMALL'],
  BIG        => [$SIZE,      'BIG'],
  DEF_BIG    => [$SIZE,      undef],
  AUTO       => [$AUTO,      'AUTO'],
  NO_AUTO    => [$AUTO,      'NO_AUTO'],
  DEF_AUTO   => [$AUTO,      undef],
  CONVERTED  => [$INTERNAL,  'CONVERTED'],
  IS_REDUCED => [$RED_STATE, 'IS_REDUCED'],
);

my @DEF_TAG = qw(DEF_MIXED DEF_REDUCE DEF_BIG DEF_AUTO);

my $ID = 01;

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my ($self, @frac, @tags, $tag, $decimal, $p1, $p2, $p3);
  if (_is_decimal($_[0]) and _is_decimal($_[1]) and _is_decimal($_[2])) {
    my $sign = $_[0] / abs($_[0]);
    @tags = _tags(@_[3 .. $#_]);
    ($decimal, $p1, $p2, $p3) = _fix_num(\@tags, @_[0 .. 2]);
    ($p1, $p2, $p3) = (abs($p1), abs($p2), abs($p3));
    @frac = ($p1 * $p3 + $p2, $sign * $p3);
    @frac = _de_decimal(@frac, \@tags) if $decimal;
  }
  elsif (_is_decimal($_[0]) and _is_decimal($_[1])) {
    @tags = _tags(@_[2 .. $#_]);
    ($decimal, @frac) = _fix_num(\@tags, @_[0 .. 1]);
    @frac = _de_decimal(@frac, \@tags) if $decimal;
    @frac = _simplify_sign(@frac);
  }
  elsif (_is_decimal($_[0])) {
    {
      @tags = _tags(@_[1 .. $#_]);
      ($decimal, $p1) = _fix_num(\@tags, $_[0]);
      @frac = ($p1, 1), last if not $decimal;
      (@frac[0 .. 1], $tag) = _from_decimal($p1);
      @tags = _tags(@tags, $tag);
      ($decimal, @frac) = _fix_num(\@tags, @frac);
      @frac = _de_decimal(@frac, \@tags) if $decimal;
    }
  }
  elsif ($_[0] =~ /\s*([\+\-]?)\s*([0-9e\.\+\-]+)\s+([0-9e\.\+\-]+)\s*\/\s*([0-9e\.\+\-]+)/) {
    my $sign = $1 . '1';
    @tags = _tags(@_[1 .. $#_]);
    ($decimal, $p1, $p2, $p3) = _fix_num(\@tags, $2, $3, $4);
    ($p1, $p2, $p3) = (abs($p1), abs($p2), abs($p3));
    @frac = ($p1 * $p3 + $p2, $sign * $p3);
    @frac = _de_decimal($p1 * $p3 + $p2, $sign * $p3, \@tags) if $decimal;
  }
  elsif ($_[0] =~ /\s*([0-9e\.\+\-]+)\s*\/\s*([0-9e\.\+\-]+)/) {
    @tags = _tags(@_[1 .. $#_]);
    ($decimal, @frac) = _fix_num(\@tags, $1, $2);
    @frac = _de_decimal(@frac, \@tags) if $decimal;
    @frac = _simplify_sign(@frac);
  }
  else {
    croak("\"$_[0]\" is of unknown format");
  }
  croak("Can not have 0 as the denominator") if $frac[1] == 0;
  if (_tag($REDUCE, \@tags) ne 'NO_REDUCE' and _tag($RED_STATE, \@tags) ne 'IS_REDUCED') {
    my $not_reduced;
    ($not_reduced, @frac) = _reduce(@frac);
    @frac = _fix_auto('DOWN', \@tags, @frac) if $not_reduced and _tag($AUTO, \@tags) eq 'AUTO';
  }
  @tags[$RED_STATE] = undef if _tag($RED_STATE, \@tags) eq 'IS_REDUCED';
  $self->{frac} = \@frac;
  $self->{tags} = \@tags;
  bless($self, $class);
  return $self;
}

sub string {
  my $self = shift;
  my @frac;
  my $mixed = _tag($OUTFORMAT, [$_[0]], $self->{tags});
  if ($mixed eq 'MIXED') {
    @frac = $self->list('MIXED');
    my $string = "";
    $string .= "$frac[0]"          if $frac[0] != 0;
    $string .= " "                 if $frac[0] != 0 and $frac[1] != 0;
    $string .= "$frac[1]/$frac[2]" if $frac[1] != 0;
    $string = "0" if $string eq '';
    return $string;
  }
  elsif ($mixed eq 'MIXED_RAW') {
    @frac = $self->list('MIXED');
    return "$frac[0] $frac[1]/$frac[2]";
  }
  elsif ($mixed eq 'RAW') {
    @frac = $self->list;
    return ($frac[0] >= 0 ? '+' : '') . "$frac[0]/$frac[1]";
  }
  else {
    @frac = $self->list;
    return "$frac[0]/$frac[1]";
  }
}

sub list {
  my $self = shift;
  my @frac = @{ $self->{frac} };
  if ($_[0] eq "MIXED") {
    my $whole = $frac[0] / $frac[1];
    $whole   = int($whole) if not ref($frac[0]);
    $frac[0] = abs($frac[0] - $frac[1] * $whole);
    @frac    = ($whole, @frac);
  }
  foreach (@frac) { s/^\+//; }
  return @frac;
}

sub reduce {
  my $self = shift;
  my ($undef, @frac) = _reduce(@{ $self->{frac} });
  return Math::FractionManip->new(@frac, @{ $self->{tags} });
}


sub decimal {
  my $self = shift;
  my @frac = @{ $self->{frac} };
  return $frac[0] / $frac[1] if not ref($frac[0]);
  return Math::BigFloat->new(Math::BigFloat::bdiv($frac[0], $frac[1], $DEF{CURRENT}{DIGITS})) if ref($frac[0]);
}

sub num {
  my $self = shift;
  my @frac = @{ $self->{frac} };
  return $frac[0] / $frac[1] if not ref $frac[0];
  return Math::BigFloat->new(Math::BigFloat::bdiv($frac[0], $frac[1], $DEF{CURRENT}{DIGITS})) if ref($frac[0]);
}

## For the next three methods:
# If used on the object use the tags of the object
# If given a class use the dafault tags,
# .... if a default set is specified then return for that set.

sub is_tag {
  my $self    = shift;
  my $tag     = shift;
  my $default = 1 if $_[0] eq 'INC_DEF';
  my $is_tag  = 0;
  my @tags;
  {
    $is_tag = 0, last if not $TAGS{$tag};    #if there is no such tag ret=0
    my ($num, $tag) = @{ $TAGS{$tag} };
    if (ref($self) eq "Math::FractionManip") {
      @tags   = @{ $self->{tags} };
      $is_tag = 1, last if $tags[$num] eq $tag;
      $is_tag = undef, last if $tags[$num] eq undef and not $default;
      $is_tag = -1, last if $DEF{CURRENT}{TAGS}[$num] eq $tag
        and $tags[$num] eq undef and $default;
      $is_tag = 0;
    }
    else {
      my $set;
      $set = 'CURRENT' unless $set = $_[0];
      $set = 'BLANK'   unless exists $DEF{$set};
      $is_tag = 1, last if $DEF{$set}{TAGS}[$num] eq $tag;
      $is_tag = 0;
    }
  }
  return $is_tag;
}

sub tags {
  my $self = shift;
  my @tags;
  if (ref($self) eq "Math::FractionManip") {
    my $inc_def = 1 if $_[0] eq 'INC_DEF';
    @tags = @{ $self->{tags} }[0 .. $TAG_END];
    my $num;
    foreach $num (0 .. $#tags) {
      $tags[$num] = $DEF_TAG[$num] if $tags[$num] eq undef and not $inc_def;
      $tags[$num] = $DEF{CURRENT}{TAGS}[$num] if $tags[$num] eq undef and $inc_def;
    }
  }
  elsif (ref($self) ne "Math::FractionManip") {
    my $set;
    $set = 'CURRENT' unless $set = $_[0];
    $set = 'BLANK'   unless exists $DEF{$set};
    @tags = @{ $DEF{$set}{TAGS} };
  }
  return @tags;
}

sub digits {
  my $self = shift;
  my $set;
  $set = 'CURRENT' unless $set = $_[0];
  $set = 'BLANK'   unless exists $DEF{$set};
  return $DEF{$set}{DIGITS};
}

###############################
# These methods are used for managing default sets.

sub sets {
  my $self = shift;
  return keys %DEF;
}

sub name_set {
  shift;
  return $DEF{CURRENT}{NAME} if not $_[0];
  $DEF{CURRENT}{NAME} = $_[0] if $_[0];
}

sub exists_set {
  return exists $DEF{ $_[1] };
}

sub use_set {
  my $self = shift;
  my $name = shift;
  if (exists $DEF{$name} and not $DEF{$name}{READONLY}) {
    $DEF{CURRENT} = $DEF{$name};
    return $name;
  }
  else {
    return undef;
  }
}

sub temp_set {
  my $self = shift;
  my $name = shift;
  if (not $name) {
    $ID++;
    $name = "\cI\cD$ID";
    $self->copy_set('CURRENT', $name);
    $self->copy_set('DEFAULT', 'CURRENT');
    return $name;
  }
  else {    #if $name;
    my $return = $self->copy_set($name, 'CURRENT');
    $self->del_set($name);
    return $return;
  }
}

sub load_set {
  my $self = shift;
  if (exists $DEF{ $_[0] }) {
    $self->copy_set($_[0], 'CURRENT') if exists $DEF{ $_[0] };
    return $_[0];
  }
  else {
    return undef;
  }
}

sub save_set {
  my $self = shift;
  my $name;
  $name = $DEF{CURRENT}{NAME} unless $name = shift;
  ++$ID, $name = "\cI\cD:$ID" if not $name or $name eq 'RAND';
  return $self->copy_set('CURRENT', $name) && $name;
}

sub copy_set {
  shift;
  my ($name1, $name2) = @_;
  if ($DEF{$name2}{READONLY} or $name2 eq 'BLANK' or not exists $DEF{$name1}) {
    return 0;
  }
  else {
    $DEF{$name2}         = {};                        # kill any links from use;
    $DEF{$name2}{TAGS}   = [@{ $DEF{$name1}{TAGS} }];
    $DEF{$name2}{DIGITS} = $DEF{$name1}{DIGITS};
    $DEF{$name2}{NAME} = $name2 unless $name2 eq 'CURRENT';
    $DEF{$name2}{NAME} = $name1 if $name2 eq 'CURRENT';
    return 1;
  }
}

sub del_set {
  if (exists $DEF{ $_[1] } and not $DEF{ $_[1] }{SYSTEM}) {
    delete $DEF{ $_[1] };
    return $_[1];
  }
}

###############################
# All of the modify methods are not meant to return anything, they modify
# the object being referenced.

# This method works almost like the new method except that it takes an
# object as an argement and will modify it instead of creating a new
# object, also any tags assosated with the object are left in tact
# unless a new tag is given to override the old.
sub modify {
  my $me = shift;
  my $self;
  my @tags = @{ $me->{tags} };
  $self = Math::FractionManip->new(@_, @tags, @_); # The extra @_ is there to override tags
  $me->{frac} = $self->{frac};
  $me->{tags} = $self->{tags};
}

# XXX This method appears to break things? -GB
sub modify_digits {
  my $self = shift;
  $DEF{CURRENT}{DIGITS} = shift;
}

sub modify_reduce {
  my $me   = shift;
  my $self = $me->reduce;
  $me->{frac} = $self->{frac};
  $me->{tags} = $self->{tags};
}

sub modify_num {
  my $self = shift;
  $self->[0] = $_[0];
}

sub modify_den {
  my $self = shift;
  $self->[1] = $_[0];
}

sub modify_tag {
  my $self = shift;
  my ($return, @return);
  my $newtag;
  foreach $newtag (@_) {
    my $tagnum = _tagnum($newtag);
    if ($tagnum == -1) {
      push @return, undef;
    }
    elsif (ref($self) eq "Math::FractionManip") {
      my @frac    = @{ $self->{frac} };
      my @tags    = @{ $self->{tags} };
      my @newtags = _tags(@tags, $newtag);

      # Now transform the Fraction based on the new tag.
      if ($tagnum == $SIZE) {
        my $newtag = _tag($SIZE, \@newtags);
        @frac = map { "$_" + 0 } @frac              if $newtag eq 'SMALL';
        @frac = map { Math::BigInt->new($_) } @frac if $newtag eq 'BIG';
      }
      elsif ($tagnum == $REDUCE) {
        (undef, @frac) = _reduce(@frac) if _tag($REDUCE, \@newtags) eq 'REDUCE';
      }

      # Finally Modify the Fraction
      $self->{frac} = \@frac;
      $self->{tags} = \@newtags;
    }
    else {
      $DEF{CURRENT}{TAGS}[$tagnum] = $newtag;
    }
    push @return, $newtag;
  }
  return @return;
}

###############################
# These methods are meant to be called with the overload operators.

sub add {
  my @frac1 = @{ $_[0]->{frac} };
  my @tags1 = @{ $_[0]->{tags} };
  my (@frac2, @frac, @tags2, $frac);
  my $skipauto = 0;
  @frac2 = @{ $_[1]->{frac} }, @tags2 = @{ $_[1]->{tags} } if ref($_[1]) eq "Math::FractionManip";
  @frac2 = _from_decimal($_[1]), $tags2[$INTERNAL] = 'CONVERTED' if ref($_[1]) ne "Math::FractionManip";
  my @tags = _tags_preserve([@tags1], [@tags2]);

LOOP: {
    if (_tag($REDUCE, \@tags) eq 'NO_REDUCE') {
      @frac = ($frac1[0] * $frac2[1] + $frac2[0] * $frac1[1], $frac1[1] * $frac2[1]);
    }
    else {

      # Taken from Knuth v2 (rev 2), p313.
      # It will always return a reduced fraction.
      my $gcd1 = _gcd($frac1[1], $frac2[1]);
      my $tmp = $frac1[0] * ($frac2[1] / $gcd1) + $frac2[0] * ($frac1[1] / $gcd1);
      my $gcd2 = _gcd($tmp, $gcd1);
      @frac = ($tmp / $gcd2, ($frac1[1] / $gcd1) * ($frac2[1] / $gcd2));
      $tags[$RED_STATE] = 'IS_REDUCED';
    }
    if ((_tag($AUTO, \@tags) eq 'AUTO') and (not $skipauto) and
      ($tags[$SIZE] eq 'SMALL') and ($frac[0] =~ /[eE]/ or $frac[1] =~ /[eE]/))
    {
      (@frac1[0 .. 1], @frac2[0 .. 1]) = map { Math::BigInt->new($_) } (@frac1, @frac2);
      $tags[$SIZE] = 'BIG';
      $skipauto = 1;
      redo LOOP;
    }
  }
  return Math::FractionManip->new(@frac, @tags);
}

sub sub {
  my ($frac1, $frac2) = ($_[$_[2]], $_[not $_[2]]);    # swap if needed
  $frac1 = Math::FractionManip->new($frac1, 'CONVERTED') if ref($frac1) ne "Math::FractionManip";
  $frac2 = Math::FractionManip->new($frac2, 'CONVERTED') if ref($frac2) ne "Math::FractionManip";

  $frac2 = Math::FractionManip->new($frac2->{frac}[0], -$frac2->{frac}[1], @{ $frac2->{tags} });

  return $frac1 + $frac2;
}

sub mul {
  my @frac1 = @{ $_[0]{frac} };
  my @tags1 = @{ $_[0]{tags} };
  my (@frac2, @frac, @tags2);
  @frac2 = @{ $_[1]->{frac} }, @tags2 = @{ $_[1]->{tags} } if ref($_[1]) eq "Math::FractionManip";
  @frac2 = (_from_decimal($_[1])), $tags2[$INTERNAL] = 'CONVERTED' if ref($_[1]) ne "Math::FractionManip";
  my @tags     = _tags_preserve([@tags1], [@tags2]);
  my $skipauto = 0;
LOOP: {
    if (_tag($REDUCE, \@tags) eq 'NO_REDUCE') {
      @frac = ($frac1[0] * $frac2[0], $frac1[1] * $frac2[1]);
    }
    else {
      my ($gcd1, $gcd2) = (_gcd($frac1[0], $frac2[1]), _gcd($frac2[0], $frac1[1]));
      $frac[0]          = ($frac1[0] / $gcd1) * ($frac2[0] / $gcd2);
      $frac[1]          = ($frac1[1] / $gcd2) * ($frac2[1] / $gcd1);
      $tags[$RED_STATE] = 'IS_REDUCED';
    }
    if ((_tag($AUTO, \@tags) eq 'AUTO') and (not $skipauto) and
      ($tags[$SIZE] eq 'SMALL') and ($frac[0] =~ /[eE]/ or $frac[1] =~ /[eE]/))
    {
      (@frac1[0 .. 1], @frac2[0 .. 1]) = map { Math::BigInt->new($_) } (@frac1, @frac2);
      $tags[$SIZE] = 'BIG';
      $skipauto = 1;
      redo LOOP;
    }
  }
  return Math::FractionManip->new(@frac, @tags);
}

sub div {
  my ($frac1, $frac2) = ($_[$_[2]], $_[not $_[2]]);    # swap if needed
  $frac1 = Math::FractionManip->new($frac1, 'CONVERTED') if ref($frac1) ne "Math::FractionManip";
  $frac2 = Math::FractionManip->new($frac2, 'CONVERTED') if ref($frac2) ne "Math::FractionManip";

  $frac2 = Math::FractionManip->new($frac2->{frac}[1], $frac2->{frac}[0], @{ $frac2->{tags} });

  #Makes a copy of the fraction with the num and den switched.

  return $frac1 * $frac2;
}

sub pow {
  my (@frac, @frac1, @tags1);
  @frac1 = @{ $_[$_[2]]->{frac} }, @tags1 = @{ $_[$_[2]]->{tags} } if ref($_[$_[2]]) eq "Math::FractionManip";
  @frac1 = _from_decimal($_[$_[2]]) if ref($_[$_[2]]) ne "Math::FractionManip";
  my $frac2;
  $frac2 = $_[not $_[2]]->decimal if ref($_[not $_[2]]) eq "Math::FractionManip";
  $frac2 = $_[not $_[2]] if ref($_[not $_[2]]) ne "Math::FractionManip";
  my @tags     = @tags1;
  my $skipauto = 0;

LOOP: {
    @frac = ($frac1[0] ** $frac2, $frac1[1] ** $frac2);

    if ((_tag($AUTO, \@tags) eq 'AUTO') and (not $skipauto) and
      ($tags[$SIZE] eq 'SMALL') and ($frac[0] =~ /[eE]/ or $frac[1] =~ /[eE]/))
    {
      @frac1       = map { Math::BigInt->new($_) } @frac1;
      $tags[$SIZE] = 'BIG';
      $skipauto    = 1;
      redo LOOP;
    }
  }

  return Math::FractionManip->new(@frac, @tags);
}

sub sqrt {
  my $self = shift;
  my @frac = @{ $self->{frac} };
  my @tags = @{ $self->{tags} };
  my $ans;
  if (ref($frac[0])) {
    $frac[0] = Math::BigFloat->new(Math::BigFloat::fsqrt($frac[0], $DEF{CURRENT}{DIGITS}));
    $frac[1] = Math::BigFloat->new(Math::BigFloat::fsqrt($frac[1], $DEF{CURRENT}{DIGITS}));
  }
  else {
    @frac = (sqrt($frac[0]), sqrt($frac[1]));
  }
  return Math::FractionManip->new(@frac, @tags);
}

sub abs {
  my $self = shift;
  my @frac = @{ $self->{frac} };
  my @tags = @{ $self->{tags} };
  return Math::FractionManip->new(abs($frac[0]), abs($frac[1]), @tags, 'IS_REDUCED');
}

sub cmp {
  my @frac1 = @{ $_[0]->{frac} };
  my @tags1 = @{ $_[0]->{tags} };
  my (@frac2, @frac, @tags2, $x, $y);
  @frac2 = @{ $_[1]->{frac} }, @tags2 = @{ $_[1]->{tags} } if ref($_[1]) eq "Math::FractionManip";
  @frac2 = _from_decimal($_[1]), @tags2 = qw(CONVERTED) if ref($_[1]) ne "Math::FractionManip";
  my @tags = _tags_preserve([@tags1], [@tags2]);
  if (_tag($REDUCE, \@tags) == 'NO_REDUCE') {
    $x = $frac1[0] * $frac2[1];
    $y = $frac2[0] * $frac1[1];
  }
  else {
    my $gcd1 = _gcd($frac1[1], $frac2[1]);
    $x = $frac1[0] * ($frac2[1] / $gcd1);
    $y = $frac2[0] * ($frac1[1] / $gcd1);
  }
  return $x <=> $y;
}

################################
# These functions are internal

sub _fix_num {
  my $tagsref = shift;
  my @return  = @_;
  my $auto    = _tag($AUTO, $tagsref) eq 'AUTO';
  $tagsref->[$SIZE] = _tag($SIZE, $tagsref);
  $tagsref->[$SIZE] = 'SMALL' if $auto;
  my $num;
  my $decimal = 0;
  foreach $num (@return) {
    if (ref($num) eq "Math::BigFloat") {
      $tagsref->[$SIZE] = 'BIG' unless $auto;
      $decimal = 1;
    }
    elsif (ref($num) eq "Math::BigInt") {
      $tagsref->[$SIZE] = 'BIG' unless $auto;
    }
    elsif (ref($num)) {

      # do nothing
    }
    elsif ($num =~ /[\.\e]/) {
      $decimal = 1;
    }
    if ($auto) {
      $num =~ /[\+\-]?\s*0*([0-9]*)\s*\.?\s*([0-9]*)0*/;
      my $length = length($1) + length($2);
      $tagsref->[$SIZE] = 'BIG' if $length > 15;
    }
  }
  if ($tagsref->[$SIZE] eq 'BIG') {
    @return = map { Math::BigInt->new("$_") } @return   if not $decimal;
    @return = map { Math::BigFloat->new("$_") } @return if $decimal;
  }
  if ($tagsref->[$SIZE] eq 'SMALL' and $auto) {
    @return = map { "$_" + 0 } @return;
  }
  return ($decimal, @return);
}

sub _fix_auto {
  my $direction = shift;
  my $tagsref   = shift;
  my @return    = @_;
  $tagsref->[$SIZE] = 'SMALL';
  my $num;
  foreach $num (@return) {
    $num =~ /[\+\-]?\s*0*([0-9]*)\s*\.?\s*([0-9]*)0*/;
    my $length = length($1) + length($2);
    $tagsref->[$SIZE] = 'BIG' if $length > 15;
  }
  if ($tagsref->[$SIZE] eq 'BIG' and $direction eq 'BOTH') {
    @return = map { Math::BigInt->new("$_") } @return;
  }
  elsif ($tagsref->[$SIZE] eq 'SMALL') {
    @return = map { "$_" + 0 } @return;
  }
  return (@return);
}

sub _is_decimal {
  return undef unless defined $_[0];
  my $return = $_[0] =~ /^\s*[\+\-0-9eE\.]+\s*$/;
  return $return;
}

sub _reduce {
  my @frac = @_;
  my $gcd  = _gcd(@frac);
  if ($gcd == 1) {
    return (0, @frac);
  }
  else {
    return (1, $frac[0] / $gcd, $frac[1] / $gcd);
  }
}

sub _simplify_sign {
  my @frac = @_;
  my $sign = 1;
  $sign = ($frac[0] / CORE::abs($frac[0])) * ($frac[1] / CORE::abs($frac[1])) if $frac[0];
  @frac = ($sign * CORE::abs($frac[0]), CORE::abs($frac[1]));
  return @frac;
}

sub _tags {
  my @return = (undef, undef);
  my ($NUM, $VALUE) = (0, 1);

  foreach (@_) {
    next if not $TAGS{$_};
    my ($num, $value) = @{ $TAGS{$_} };
    $return[$num] = $value;
  }

  return @return;
}

sub _tag {
  my $item = shift;
  my $return;
  my $ref;
  foreach $ref (@_, $DEF{CURRENT}{TAGS}) {
    last if $return = ${$ref}[$item];
  }
  return $return;
}

sub _tagnum {
  my $item = shift;
  if (exists $TAGS{$item}) {
    return $TAGS{$item}[0];
  }
  else {
    return -1;
  }
}

sub _tags_preserve {
  my @tags1 = @{ $_[0] };
  my @tags2 = @{ $_[1] };
  my @tags;
  if ($tags1[$INTERNAL] eq 'CONVERTED') {
    @tags = @tags2;
  }
  elsif ($tags2[$INTERNAL] eq 'CONVERTED') {
    @tags = @tags1;
  }
  else {
    @tags = map { $tags1[$_] eq $tags2[$_] and $tags1[$_] } (0 .. $#tags1);
  }
  return @tags;
}

sub _gcd {
  my ($x, $y) = (CORE::abs($_[0]), CORE::abs($_[1]));
  if (ref($x)) {
    $x = Math::BigInt->new($x->bgcd($y));
  }
  else {
    {
      $x = 1, last if $y > 1e17;  # If this is so % will thinks its a zero so if
                                  # $y>1e17 will simply will basicly give up and
                                  # have it return 1 as the GCD.
      my ($x0);
      while ($y != 0) {
        $x0 = $x;
        ($x, $y) = ($y, $x % $y);

        # Note $x0 = $x, $x = $y, $y= $x % $y   Before the Swith
        $x = 1, last if ($x0 > 99999999 or $x > 999999999) and int($x0 / $x) * $x + $y != $x0;

        # This is to see if the mod operater through up on us when dealing with
        # large numbers.  If it did set the gcd = 1 and quit.
      }
    }
  }
  return $x;
}

sub _de_decimal {
  my @frac = @_;
  my @return;
  my $big = _tag($SIZE, $_[2]);
  my (@int_part, @decimal_part);
  if ($big eq "BIG") {
    my @digits = (1, 1);
    ($int_part[0], $digits[0]) = $frac[0]->fnorm =~ /(\d+)E\-(\d+)/;
    ($int_part[1], $digits[1]) = $frac[1]->fnorm =~ /(\d+)E\-(\d+)/;
    @digits = sort { $a <=> $b } @digits;
    my $factor = 10 ** $digits[1];
    @frac = (($_[0] * $factor), ($_[1] * $factor));
    chop $frac[0]; chop $frac[1];
    @frac = (Math::BigInt->new($frac[0]), Math::BigInt->new($frac[1]));
  }
  else {
    ($int_part[0], $decimal_part[0]) = $frac[0] =~ /(\d+)\.(\d+)/;
    ($int_part[1], $decimal_part[1]) = $frac[1] =~ /(\d+)\.(\d+)/;
    @decimal_part = sort { $a <=> $b } (length($decimal_part[0]), length($decimal_part[1]));
    my $factor = 10 ** $decimal_part[1];
    @frac = ($_[0] * $factor, $_[1] * $factor);
  }
  return @frac;
}

sub _from_decimal {
  my $decimal = shift;                    # the decimal (1.312671267127)
  my $big     = 'BIG' if ref($decimal);
  my ($repeat);    # flag to keep track if it is repeating or not
  my ($sign);
  my ($factor, $int_factor);
  my ($factor2);
  my ($whole_num, $whole_num_len);
  my ($int_part);                           # integer part (1)
  my ($decimal_part, $decimal_part_len);    # decimal part (312671267127)
  my ($decimal_part2);    # decimal part - last bit \/ (312671267)
  my ($pat, $pat_len);    # repeating pat (1267)
  my ($pat_lastb);        # last bit of repeating pat (127)
  my ($beg_part,   $beg_part_len);      # non-repeating part (3)
  my ($other_part, $other_part_len);    # repeating part     (1267126712127)
  my ($frac1,      $frac2, $frac3);

  my $rnd_mode = $Math::BigFloat::rnd_mode;    # to avoid problems with incon.
  $Math::BigFloat::rnd_mode = 'trunc';         # rounding

  $decimal = "$decimal";
  $decimal =~ s/\s//g;
  ($sign, $int_part, $decimal_part) = $decimal =~ /([\+\-]?)\s*(\d*)\.(\d+)$/;
  $sign .= '1';
  $decimal_part_len = length($decimal_part);
  $int_part         = "" unless $int_part;
  $factor           = '1' . '0' x (length($decimal_part));
  $factor           = Math::BigFloat->new($factor) if $big;

  # Make it a BigFloat now to simplfy latter
  $int_factor   = '1' . '0' x (length($int_part));
  $beg_part_len = 0;
OuterBlock:
  while ($beg_part_len < $decimal_part_len) {
    $beg_part   = substr($decimal_part, 0, $beg_part_len);
    $other_part = substr($decimal_part, $beg_part_len);
    $other_part_len = length($other_part);
    my $i;
    for ($i = 1; $i < ($other_part_len / 2 + 1); $i++) {
      $pat     = substr($other_part, 0, $i);
      $pat_len = $i;
      local $_ = $other_part;
      $repeat = undef;
      while (1) {
        ($_) = /^$pat(.*)/;
        my $length = length($_);

        if ($length <= $pat_len) {
          last unless $length;
          $pat_lastb = substr($pat, 0, $length);
          $repeat    = 1, last OuterBlock if $pat_lastb eq $_;
          if ($pat_lastb eq $_ - 1) {

            # this is needed to see if it really is the repeating fracton
            # we intented it to be.  If we don't do this 1.1212 would become
            # 1120/999 = 1.1211211211.
            # The first three lines converts it to a fraction and the
            # rests tests it to the actual repeating decimal/
            # The NO_REDUCE flag is their to save time as reducing large
            # fraction can take a bit of time which is unnecessary as we will
            # be converting it to a decimal.
            $decimal_part2 = substr($decimal_part, 0, $decimal_part_len - length($pat_lastb));
            $factor2 = '1' . '0' x (length($decimal_part2));
            $frac1 = Math::FractionManip->new('0' . $beg_part, 1 . 0 x $beg_part_len, 'NO_REDUCE', $big);
            $frac2 = Math::FractionManip->new('0' . $pat, 9 x $pat_len . 0 x $beg_part_len, 'NO_REDUCE', $big);
            $frac3 = $frac1 + $frac2;
            my $what_i_get    = $frac3->decimal;
            my $places        = length($what_i_get);
            my $decimal_p_tmp = $decimal_part2 if not $big;
            $decimal_p_tmp = Math::BigFloat->new($decimal_part2) if $big;
            my $what_i_should_get = (($decimal_p_tmp) / $factor2) . "$pat" x ($places);

            # The rest of this is doing nothing more but trying to compare
            # the what_i_get and what_i_should_get but becuse the stupid
            # BigFloat module is so pragmentic all this hopla is nessary
            $what_i_should_get = Math::BigFloat->new($what_i_should_get) if $big;
            $what_i_should_get = $what_i_should_get->fround(length($what_i_get) - 1) if $big;
            $what_i_should_get = Math::BigFloat->new($what_i_should_get) if $big;
            # ^^ Needed because the fround method does not return a BigFloat object!

            my $pass = "$what_i_get" eq "$what_i_should_get" if $big;
            $pass = $what_i_get == $what_i_should_get if not $big;
            $repeat = 1, last OuterBlock if ($pass);
          }
        }
      }
    }
    $beg_part_len++;
  }
  if ($repeat) {
    $frac1 = Math::FractionManip->new('0' . $beg_part, 1 . 0 x $beg_part_len, $big);
    $frac2 = Math::FractionManip->new('0' . $pat, 9 x $pat_len . 0 x $beg_part_len, $big);
    $int_part = Math::FractionManip->new('0' . $int_part, 1, 'BIG') if $big;
    $frac3    = $sign * ($int_part + $frac1 + $frac2);
    return @{ $frac3->{frac} };
  }
  else {
    return ($decimal * $factor, $factor, $big);
  }
  $Math::BigFloat::rnd_mode = $rnd_mode;    # set it back to what it was.
}

1;
__END__

=head1 SYNOPSIS

  use Math::FractionManip;

  my $w = Math::FractionManip->new(0.66667); # 2/3
  my $x = Math::FractionManip->new(1, 2); # 1/2
  my $y = Math::FractionManip->new(4, 3); # 4/3
  my $z = Math::FractionManip->new(4, 3, 'MIXED'); # 1 1/3

  print "$x + $y = ", $x + $y, "\n";
  print "$x * $y = ", $x * $y, "\n";
  print $x->num, "\n"; # 0.5

=head1 DESCRIPTION

This module is the resurrection of C<Math::Fraction> which disappeared
from CPAN and wouldn't install anyway. Now that is fixed.

The decimal to fraction functionality of this module is too handy to
not have imho. The module L<Number::Fraction> does a proper job of
overloaded arithmetic. But it does not handle decimals in the
constructor. So the main reason for this module re-appearing is its
decimal to fraction functionality.

The source code is extremely ugly and throws warnings all over. But it
seems to work! Beware looking under the hood, though.

Fwiw, parts of the following original documentation are confusing.
YMMV

=over 4

=item *

Add, subtract, multiply, and divide, etc. fractions just like you
would normal numbers.

=item *

Convert a decimal, including repeating ones, into a fraction.

=item *

Control how the fraction is displayed.

=item *

Use arbitrary size numbers in the numerator and the denominator.

=back

=head2 Usage

The constructor can have the following arguments:

=over 4

=item *

Numerator, Denominator[, TAGS]

=item *

Number, Numerator, Denominator[, TAGS]

=item *

Decimal[, TAGS]

=item *

"Numerator/Denominator"[, TAGS]

=item *

"Number Numerator/Denominator"[, TAGS]

=back

These can be any real number; however if you
enter a negative number for anything but the First Number,
that negative will be ignored.

TAGS can equal 0 or one or more of the following:

=over 4

=item NORMAL|MIXED|MIXED_RAW|RAW|DEF_MIXED

Control how the fraction is displayed.

=over 8

=item NORMAL

Display in the #/# form.

=item MIXED_RAW

Display in the # #/# form.

=item MIXED

The same as MIXED_RAW but if one part is equal to 0 it will leave it off.

=item RAW

The same as NORMAL but always includes the sign.

=item DEF_MIXED

Will let it be what ever the default value is at the time.

=back

=item REDUCE|NO_REDUCE|DEF_REDUCE

Controls the automatic reduction of fraction after operations are
performed on it.

=item AUTO|NO_AUTO|DEF_AUTO

Set rather to automatically convert between BIG and SMALL as needed.

See L<Notes on the AUTO tag>.

=item SMALL|BIG|DEF_BIG

When the AUTO tag is NOT set it will set whether to use Arbitrary-Length
numbers using the Math::BigInt and Math::BigFloat packages. (The C<**>
operator will not work due to limitations of the packages.)
When the AUTO tag is set these tags will have NO effect.

(Note the default tags are NORMAL REDUCE AUTO and SMALL.)

=back

=over 4

=item Methods

=item new

=item abs

=item add

=item cmp

=item div

=item mul

=item pow

=item sqrt

=item sub

=item modify_digits

=item reduce

Return a reduced fraction but leave the original object untouched.

=item string(NORMAL|MIXED|MIXED_RAW|RAW)

Return the fraction as a string.

If no parameters are given the default display method will be used.

=item decimal|num

Return the decimal value of the fraction.

=item list|list(MIXED)

Return a list containing the fraction. If MIXED is used, then a 3 item
list is returned.

=item is_tag

Return 1 if the tag exists in the fraction. Otherwise return -1.

=item is_tag(INC_DEF)

Return 1 if the tag exists in the fraction. Return -1 if
the tag does not exist but the default is set to that, 0 otherwise.

=item tags

Return a list of the object tags.

=item tags(INC_DEF)

Return a list of the object tags. If a particular tag
is set to read a default the default tag is returned instead.

=back

=over 4

=item modify

Modify the object.  Works almost the same as the new method
but it doesn't return anything and preserves the objects tags unless
overridden by new entries.

=item modify_reduce

Same as reduce but it modifies the object instead of returning a fraction.

=item modify_num(Numerator)

Modify the fraction numerator.

=item modify_den(Denominator)

Modify the fraction denominator.

=item modify_tag(TAGS)

Modify the fraction tags.

=back

The following methods will always modify or read the Class defaults:

=over 4

=item digits

Return the default number of digits to return when doing
floating point operations with BIG numbers, if set to undef
Math::BigFloat will decide.

  modify_digits(NUM)

=back

=head2 Default Sets

Default sets are way of modifying the defaults with out effecting
other functions.  Functions that rely on the default values or modify the
default should start with a C<$set_id = temp_set> and end with a C<temp_set($set_id)>.

The following methods are meant to manage default sets and will always
work on the Class defaults:

=over 4

=item sets

Return a list of all the sets.

=item name_set

Return the name of the current set.

=item name_set(NAME)

Name the current set.

=item save_set

Save the current set based on its name as given above.

=item save_set(NAME)

Save the current set as NAME.

=item save_set(RAND)

Save the current set using a unique name.

=item load_set(NAME)

Load a set.

=item copy_set(NAME_ORG, NAME_NEW)

Copy a set. Return true if successful.

=item del_set(NAME)

Delete a set.

=item exists_set(NAME)

Return true if the set exists.

=item use_set(NAME)

Use a set. Any changes you make to the used set
will also change the original set, like a link.

=item temp_set

Load a temporary set using the default values
and return a unique id.

=item temp_set(ID)

Restore the original set based on the id.

=back

Unless otherwise specified all the set methods will return the name of
the set being worked on if it was successful, false otherwise.

=over 4

=item tags(SET)

List all the tags in SET.

=item is_tag(TAG, SET)

Return true if TAG exists in SET.

=item digits(SET)

Return what digits is set to in SET.

=back

=head2 Overloaded Operators

The following operations have been overridden and will return a
fraction:

  +  -  /  *  +  +=  -=  *=  /=  ++  -- abs

The following operations have also been overridden:

 <=> == != < <= > >=

The following operations have also been overridden; however they may
spit out nasty fractions:

  ** sqrt

Whenever you access a fraction as a string the string method
will be called. When you access it as a number the decimal method
will be called.

=head2 Notes on the AUTO tag

With the AUTO tag set Fractions will be converted between SMALL and
BIG as needed.  The BIG and SMALL tags will be B<ignored> unless you
explicitly specify NO_AUTO in order to control how the fraction is
stored.

When you give it a number it will decide if it is small enough to be
stored as a SMALL or if the fraction needs to converted to BIG.
However, in order for it to recognize a big fraction the number needs to
be in quotes. Thus,
C<Math::FractionManip-E<gt>new(7823495784957895478,781344567825678454)>
will be stored as a SMALL with some of the digits lost.

When calculating to SMALL numbers that results in a number that is too
big for SMALL the calculation is done AGAIN but this time with BIG
numbers (so that it will calculate all the digits correctly) and the
new fraction will become a BIG.

When calculating to BIG numbers that results in a number that is small
enough to be a SMALL the new fraction will become a SMALL.

Normally, the AUTO tag will save time as calculating with BIG numbers
can be quite time consuming; however it might slow things down if it
constantly converts between the two. Thus in some cases it may be wise to
turn it off.

=head1 SEE ALSO

The F<t/01-functions.t> program in this distribution

=cut
