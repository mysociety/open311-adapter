package Open311::Endpoint::Integration::UK::Peterborough::Ezytreev;

use Moo;
extends 'Open311::Endpoint::Integration::Ezytreev';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'peterborough_ezytreev';
    return $class->$orig(%args);
};

sub get_service_requests { return (); }

__PACKAGE__->run_if_script;
