use Test::More;

package Test;

use parent qw/Class::Accessor::Inherited::XS/;
__PACKAGE__->mk_inherited_accessor(qw/foo foo/);

@Test::A::ISA = qw/Test/;
@Test::B::ISA = qw/Test::A/;

package main;

is(Test::A->foo(12), 12);
is(Test::B->foo, 12);

@Test::B::ISA = qw/Test/;

is(Test::B->foo, undef);

done_testing;
