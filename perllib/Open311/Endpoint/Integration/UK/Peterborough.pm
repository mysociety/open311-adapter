package Open311::Endpoint::Integration::UK::Peterborough;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'peterborough_confirm';
    return $class->$orig(%args);
};

1;
