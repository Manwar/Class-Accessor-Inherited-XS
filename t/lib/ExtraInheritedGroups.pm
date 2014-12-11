package ExtraInheritedGroups;
use strict;
use warnings;
use base 'AccessorInstaller';

if (!$::DO_OPTIMIZE) {
    __PACKAGE__->mk_inherited_accessors('basefield');
} else {
    __PACKAGE__->mk_inherited_accessors(['basefield', 'basefield', 1]);
}

__PACKAGE__->basefield('your extra base!');

1;
