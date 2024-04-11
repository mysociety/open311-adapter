package Open311::Endpoint::Integration::UK::Bexley::Whitespace;

use Moo;
extends 'Open311::Endpoint::Integration::Whitespace';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'bexley_whitespace';
    return $class->$orig(%args);
};

sub _worksheet_message {
    my ($self, $args) = @_;

    return "Assisted collection? $args->{attributes}->{assisted_yn}\n\n" .
           "Location of containers: $args->{attributes}->{location_of_containers}\n";
}

__PACKAGE__->run_if_script;
