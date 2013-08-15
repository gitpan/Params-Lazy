use strict;
use warnings;

use Carp qw(carp croak confess);
use Test::More tests => 19;

sub lazy_death {
    eval { force($_[0]) };
    return $@ unless $_[1];
    force($_[0]);
};
use Params::Lazy lazy_death => '^;$';

my $w = '';
local $SIG{__WARN__} = sub { $w .= shift };

sub dies      { die "die in sub"           }
# test carp() even though it's not really a death, since it 
# tends to give "Attempt to free unreferenced scalar" warnings
sub carps     { carp("carp in sub")       }
sub croaks    { croak("croak in sub")     }
sub confesses { confess("confess in sub") }


like lazy_death(die("bare die")), qr/bare die/, "lazy_death die()";

$w = "";
is(
    lazy_death(carp("bare carp")),
    '',
    "a bare carp can be delayed"
);
like(
    $w, 
    qr/bare carp/,
    "...and it throws the correct warning"
);
unlike(
    $w,
    qr/Attempt to /,
    "...and no attempt to do anything with unreferenced/freed scalars"
);

like
    lazy_death(croak("bare croak")),
    qr/bare croak/,
    "lazy_death croak()";
like
    lazy_death(confess("bare confess")),
    qr/bare confess/,
    "lazy_death confess()";


like
    lazy_death(dies()),
    qr/die in sub/,
    "lazy_death(dies())";
$w = "";
is(
    lazy_death(carps()),
    '',
    "a sub that carps can be delayed"
);
like(
    $w, 
    qr/carp in sub/,
    "...and it throws the correct warning"
);
unlike(
    $w,
    qr/Attempt to /,
    "...and no attempt to do anything with unreferenced/freed scalars"
);


like
    lazy_death(croaks()),
    qr/croak in sub/,
    "lazy_death(croaks())";
like
    lazy_death(confesses()),
    qr/confess in sub/,
    "lazy_death(confesses())";

sub call_lazy_death {
    eval { lazy_death die("bare death"), 1 };
    like $@,
         qr/bare death/s,
         "eval { lazy_death(die()) }";

    eval { lazy_death dies(),            1 };
    like $@,
         qr/die in sub/s,
         "eval { lazy_death(dies()) }";

    $w = "";
    eval { lazy_death carps(), 1 };
    is($@, "", "eval { lazy_death carps() }");
    like($w, qr/carp in sub.*call_lazy_death/s);

    eval { lazy_death croaks(),          1 };
    like $@,
         qr/croak in sub.*call_lazy_death/s,
         "eval { lazy_death(croak()) }";

    eval { lazy_death confesses(),       1 };
    like $@,
         qr/confess in sub.*call_lazy_death/s,
         "eval { lazy_death(confess()) }";
}

call_lazy_death();

pass("Survived this far");

