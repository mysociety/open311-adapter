package Open311::Endpoint::Integration::UK::Bexley::Whitespace;

use Moo;
extends 'Open311::Endpoint::Integration::Whitespace';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bexley_whitespace';
    return $class->$orig(%args);
};

__PACKAGE__->run_if_script;
