package Open311::Endpoint::Integration::UK::Buckinghamshire;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'buckinghamshire_confirm';
    return $class->$orig(%args);
};

1;
