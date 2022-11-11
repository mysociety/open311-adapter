package Open311::Endpoint::Integration::UK::Brent::Echo;

use Moo;
extends 'Open311::Endpoint::Integration::Echo';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'brent_echo';
    return $class->$orig(%args);
};

1;
