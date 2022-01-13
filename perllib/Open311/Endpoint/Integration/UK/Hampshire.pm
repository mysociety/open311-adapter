package Open311::Endpoint::Integration::UK::Hampshire;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'hampshire_confirm';
    return $class->$orig(%args);
};

1;
