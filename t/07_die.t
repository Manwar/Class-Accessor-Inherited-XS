use Test::More;
use Class::Accessor::Inherited::XS;
use strict;

{
    package Jopa;
    use base qw/Class::Accessor::Inherited::XS/;
    push @Jopa::ISA, 'Jopa::B';
    use strict;

    Jopa->mk_inherited_accessors('foo');
}

sub exception (&) {
    $@ = undef;
    eval { shift->() };
    $@
}

like exception {Jopa::foo()}, qr/Usage:/;

my $arrobj = bless [], 'Jopa';
like exception {$arrobj->foo}, qr/hash-based/;

my $scalarobj = bless \(my $z), 'Jopa';
like exception {$scalarobj->foo}, qr/hash-based/;

like exception {Jopa::foo(12)},        qr/outside of root/;
like exception {Jopa::foo('Jopa::A')}, qr/outside of root/;

@Jopa::B::ISA=qw/Jopa::A/;
like exception {Jopa::foo('Jopa::B')}, qr/outside of root/;

is(Jopa->foo(42), 42);
is(Jopa::foo('Jopa'), 42);

done_testing;
