use strict;
use warnings;

use Test::More;
use Params::Lazy;

sub stress_test {
    my @orig = @_;
    my %returns;

    local $_ = "set in stress_test";
    
    my $x = force($_[0]);
    $returns{scalar} = $x;
    my @x = force($_[0]);
    $returns{list} = \@x;
    my $j = join "", "<", force($_[0]), ">";
    $returns{join} = $j;

    open my $fh, ">", \my $tmp;
    print $fh "<", force($_[0]), ">";
    close $fh;
    $returns{print} = $tmp;
    
    {
        my $w = "";
        local $SIG{__WARN__} = sub { $w .= shift };
        warn force($_[0]);
        my $file = __FILE__;
        ($returns{warn}) = $w =~ m/(\A.+?) at $file/s;
        $w = "";
        warn "<", force($_[0]), ">";
        ($returns{warn_list}) = $w =~ m/(\A.+?) at $file/s;
    }
    
    $returns{eval} = eval 'force($_[0])';
    
    is_deeply(
        \@orig,
        \@_,
        "force() doesn't touch \@_"
    );
    
    return \%returns;
}

sub run {
    my ($code, %args) = @_;
    my $times = defined($args{times}) ? $args{times} : 1;
    my @ret;
    push @ret, force($code) while $times-- > 0;
    return @ret;
}

use Params::Lazy run => '^;@', stress_test => '^;@';

{
    my $w = "";
    local $SIG{__WARN__} = sub { $w .= shift };
    run(warn("From warn"), times => 5);
    my @matched = $w =~ /(From warn)/g;
    is(@matched, 5, "warned five times");
}
{
    my $x = 0;
    my $t = 0;
    my @ret = run($x += ++$t, times => 3);
    is($x, 6);
    is($t, 3);
    is_deeply(\@ret, [1,3,6]);
}

sub contextual_return { return wantarray ? (@_, "one", "two") : "scalar: @_" }

my $ret = stress_test(rand(111), 1);

#^TODO

$ret = stress_test(scalar contextual_return("argument one", "argument two"));

is_deeply($ret, {
    list => ['scalar: argument one argument two'],
    map({ $_ => 'scalar: argument one argument two' } qw(scalar warn eval)),
    map({ $_ => '<scalar: argument one argument two>' } qw(join print warn_list))
}, "delay scalar sub(...)");

$ret = stress_test(contextual_return(1234, 12345, 123456));
my @expect = (1234, 12345, 123456, "one", "two");
is_deeply($ret, {
    scalar => 'two',
    eval   => 'two',
    list   => [@expect],
    warn   => join("", @expect),
    map({ $_ => join "", "<", @expect, ">" } qw(join print warn_list))
}, "delay sub(...)");


$ret = stress_test(scalar map("scalar map: $_", 1..5), 2);
is_deeply($ret, {
    map({ $_ => 5 } qw(scalar warn eval)),
    list   => [5],
    map({ $_ => join "", "<", 5, ">" } qw(join print warn_list))
}, "delay scalar map");

$ret = stress_test(map("map: $_", 1..5), 2);
@expect = map("map: $_", 1..5);
is_deeply($ret, {
    scalar => 'map: 5',
    eval   => 'map: 5',
    list   => [@expect],
    warn   => join("", @expect),
    map({ $_ => join "", "<", @expect, ">" } qw(join print warn_list))
}, "delay map");

$ret = stress_test("dollar under: <$_>");
my $expect = "dollar under: <set in stress_test>";
is_deeply($ret, {
    map({ $_ => $expect } qw(scalar warn eval)),
    list   => [$expect],
    map({ $_ => join "", "<", $expect, ">" } qw(join print warn_list))
}, "delay qq{\$_}");

$ret = stress_test(do { my $x = sub { shift }->("from do"); $x }, 4);
is_deeply($ret, {
    map({ $_ => 'from do' } qw(scalar warn eval)),
    list   => ['from do'],
    map({ $_ => join "", "<", 'from do', ">" } qw(join print warn_list))
}, "delay do {...}");

sub return_a_list { qw(a 1 b 2) }
my @ret = run({ return_a_list });
is_deeply(\@ret, [{qw(a 1 b 2)}] );

our $where;
sub passover {
    my $delay = shift;
    $where .= 1;
    return takes_delayed($delay);
}
sub takes_delayed {
    my $d = shift;
    $where .= 2;
    force($d);
    sub { force($d) }->();
    if ( $] >= 5.010 ) {
        eval q{ my    $_ = 4; force($d) };
        eval q{ use feature 'state'; state $_ = 5; force($d) };
    }
    else {
        $where .= 33;
    }
    sub { our   $_ = 6; force($d) }->();
    sub { our $_; local $_ = 7; force($d) }->();
    $where .= 8;
};
use Params::Lazy passover => '^';

{
    $_ = 3;
    passover($where .= $_);
}
is($where, 123333678, "can pass delayed arguments to other subs and use them");

sub return_delayed { return shift }
use Params::Lazy return_delayed => '^;@';

my $delay = "";
my $d = do {
    my $foo = "_1_";
    my $f = return_delayed($delay .= $foo);
    is($delay, "", "sanity test");
    force($f);
    is($delay, "_1_", "can return a delayed argument and use it");
    force($f);
    is($delay, "_1__1_", "..multiple times");
    $f;
};

{
    my $w = "";
    local $SIG{__WARN__} = sub { $w .= shift };
    force($d);
    is($delay, "_1__1_", "Delayed arguments are not closures");
    like(
        $w,
        qr/Use of uninitialized value(?: \$foo)? in concatenation/,
        "Warns if a delayed argument used a variable that went out of scope"
    );
}

use lib 't/lib';
if ($] >= 5.010) {
    require lexical_topic_tests;
}

done_testing;
