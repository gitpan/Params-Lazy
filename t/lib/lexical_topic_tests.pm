{
    my $_ = "lexical"; 
    my $ret = stress_test("my dollar under: <$_>");
    my $expect = "my dollar under: <lexical>";
    is_deeply($ret, {
        map({ $_ => $expect } qw(scalar warn eval)),
        list   => [$expect],
        map({ $_ => join "", "<", $expect, ">" } qw(join print warn_list))
    }, "my \$_ = ...; delay qq{\$_}");
}

{
    $where = "";
    my $_ = 3;
    passover($where .= $_);
    
    is(
        $where,
        123333338,
        "...and it grabs the right version of a variable"
    );
}

$d = do {
    my $_ = "_55_";
    my $f = return_delayed("<$_>");
    is(
        force($f),
        "<$_>",
        "can return a delayed argument referencing a lexical \$_ and use it"
    );
    
    is(
        eval 'force($f)',
        "<$_>",
        "eval 'force(delayed arg that references a lexical)'"
    );
    
=begin Segfaults, Not actually supported, pathological
    for my $sub (
        sub { force($d) },
        sub { my    $_ = "_66_"; force($d) },
        sub { state $_ = "_77_"; force($d) },
        sub { our   $_ = "_88_"; force($d) },
        sub { our $_; local $_ = "_99_"; force($d) },
        )
    {
        my $w = "";
        local $SIG{__WARN__} = sub { $w .= shift };

        $sub->();
        like(
            $w,
            qr/Use of uninitialized value \$_/,
            ""
        );
    }
=cut
};
