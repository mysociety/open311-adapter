package Open311::Endpoint::Integration::UK::Bexley::ConfirmTrees;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bexley_confirm_trees';
    return $class->$orig(%args);
};

1;
