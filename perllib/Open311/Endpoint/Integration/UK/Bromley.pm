package Open311::Endpoint::Integration::UK::Bromley;

use Moo;
extends 'Open311::Endpoint::Integration::Echo';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bromley_echo';
    return $class->$orig(%args);
};

1;

