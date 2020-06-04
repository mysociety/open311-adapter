package Open311::Endpoint::Integration::UK::Peterborough::Bartec;

use Moo;
extends 'Open311::Endpoint::Integration::Bartec';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'peterborough_bartec';
    return $class->$orig(%args);
};

__PACKAGE__->run_if_script;
