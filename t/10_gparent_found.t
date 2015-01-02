use Test::More;

package Base;

use Class::Accessor::Inherited::XS {
    inherited => [qw/foo/],
};

@Child1::ISA = qw/Base/;
@Child2::ISA = qw/Child1/;
@Child3::ISA = qw/Child2/;
@Child4::ISA = qw/Child3/;

package main;

is(Child3->foo, undef);

#exercise 'update_cache' behaviour w.r.t adding new junctions

is(Base->foo(42), 42);
is(Child2->foo, 42);
is(Child3->foo, 42);

is(Child2->foo(17), 17);
is(Child3->foo, 17);
is(Child1->foo, 42);

is(Base->foo(11), 11);
is(Child1->foo, 11);
is(Child2->foo, 17);
is(Child3->foo, 17);

is(Child2->foo(23), 23);
is(Child1->foo, 11);
is(Child3->foo, 23);

is(Child4->foo, 23);
is(Child3->foo(77), 77);
is(Child4->foo, 77);
is(Child2->foo, 23);

# exercise 'update_cache' behaviour w.r.t clearing values

#is(Child3->foo(undef), undef);
#is(Child4->foo, 23);
#is(Child3->foo, 23);

done_testing;
