use Test::More;
use Class::Accessor::Inherited::XS;
use strict;

{
    package Jopa;
    use base qw/Class::Accessor::Inherited::XS/;

    sub new { return bless {}, shift }
    sub foo { 42 }

    Jopa->mk_inherited_accessors(qw/a/);
}

{
    package JopaChild;
    our @ISA = qw/Jopa/;
}

{
    package Other;
    sub new { return bless {}, shift }
    sub a { 123 }
}

{
    package JopaClass;
    use base qw/Class::Accessor::Inherited::XS/;
    sub new { return bless {}, shift }
    JopaClass->mk_class_accessors(qw/a/);
}

my $o = new Jopa;
$o->{a} = 1;

for (1..3) {
    is($o->a, 1);
}

for (1..3) {
    is($o->a(6), 6);
}

my $u = new Jopa;
Jopa->a(40);
$u->a(50);

my $n = new Other;

my @res = (6, 6, 50, 6, 123, 6);
for ($o, $o, $u, $o, $n, $o) {
    is($_->a, shift @res);
}

@res = (40, 40, 123, 40);
for ('Jopa', 'Jopa', 'Other', 'Jopa') {
    is($_->a, shift @res);
}

my $jc = new JopaClass;
$jc->{a} = 77;
JopaClass->a(70);

@res = (6, 6, 70, 6);
for ($o, $o, $jc, $o) {
    is($_->a, shift @res);
}

@res = (40, 40, 70, 6);
for ('Jopa', 'Jopa', 'JopaClass', $o) {
    is($_->a, shift @res);
}

*main::a = *JopaClass::a;

@res = (40, 40, 70, 6);
for ('Jopa', 'Jopa', __PACKAGE__, $o) {
    is($_->a, shift @res);
}

@res = (40, 40, 6);
for ('Jopa', 'Jopa', \12, $o) {
    eval { is($_->a, shift @res) };
}

@res = (40, 40, 40, 40, 40);
for ('Jopa', 'Jopa', 'JopaChild', 'Jopa', 'JopaChild') {
    is($_->a, shift @res);
}

done_testing;
