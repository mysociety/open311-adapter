package Open311::Endpoint::Integration::UK::Aberdeenshire;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'aberdeenshire_confirm';
    return $class->$orig(%args);
};

sub _description_for_defect {
    my ($self, $defect, $service) = @_;

    return 'Defect type: ' . $service->service_name;
}

1;
