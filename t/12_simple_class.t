use Test::More;
use strict;

{
    package Jopa;
    use base qw/Class::Accessor::Inherited::XS/;
    use Class::Accessor::Inherited::XS class => ['foo'];
    __PACKAGE__->mk_class_accessors('bar');

    sub new { return bless {}, shift }
}

my $o = Jopa->new;

is(Jopa->foo, undef);
is($o->foo, undef);

is(Jopa->foo(12), 12);
is($o->foo, 12);
is(Jopa->foo, 12);

push @Jopa::Foo::ISA, 'Jopa';
is(Jopa::Foo->foo, 12);

my $foo = 42;
is(Jopa::Foo->foo($foo), 42);

$foo++;
is(Jopa->foo, 42);

$Jopa::foo = -1;
is(Jopa->foo, 42);

is(Jopa->bar(70), 70);

done_testing;
