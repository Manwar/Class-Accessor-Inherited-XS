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

is(Child3->foo(12), 12);
is(Child3->foo(13), 13);

is(Child3->foo, 13);
is(Child4->foo, 13);

is(Child1->foo(undef), undef);
is(Child1->foo, undef);
is(Child2->foo, undef);

is(Child1->foo(12), 12);
is(Child2->foo, 12);

is(Child1->foo(undef), undef);
is(Child1->foo, undef);
is(Child2->foo, undef);

done_testing;
