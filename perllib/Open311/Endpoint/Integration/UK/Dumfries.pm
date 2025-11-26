package Open311::Endpoint::Integration::UK::Dumfries;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';
with 'Role::Memcached';

use Encode;
use JSON::MaybeXS;
use Path::Tiny;

around BUILDARGS => sub {
    my ( $orig, $class, %args ) = @_;
    $args{jurisdiction_id} = 'dumfries_alloy';
    return $class->$orig(%args);
};

1;
