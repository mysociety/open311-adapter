package Open311::Endpoint::Integration::UK::Hounslow;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'hounslow_confirm';
    return $class->$orig(%args);
};

1;
