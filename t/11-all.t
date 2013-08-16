use strict;
use warnings;

use Test::More;

use FindBin qw($Bin);

# Re-run all the tests. 

my $pkg = "a";
for my $file (grep /[0-9]{2}-/, glob("$Bin/*.t")) {
    next if $file =~ /\Q11-all.t/;
    # Handwritten TAP
    next if $file =~ /\Q01-basics.t\E|\Q02-min.t\Q/;
    my $e;
    TODO: {
        local $TODO = "Need to diagnose"
            if $file =~ /\Qdie.t/;
        subtest $file => sub {
            eval qq{
                package Params::Lazy::Tests::$pkg;
                do q{$file};
            };
            $e = $@;
            $pkg++;
        };
    }
    is($e, '', "no errors from $file");
}

done_testing;
