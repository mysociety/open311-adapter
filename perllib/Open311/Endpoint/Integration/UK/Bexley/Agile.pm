package Open311::Endpoint::Integration::UK::Bexley::Agile;

use Moo;
extends 'Open311::Endpoint::Integration::Agile';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bexley_agile';
    return $class->$orig(%args);
};

__PACKAGE__->run_if_script;
