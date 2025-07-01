package Open311::Endpoint::Integration::UK::Aberdeenshire;

use Moo;
use Try::Tiny;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'aberdeenshire_confirm';
    return $class->$orig(%args);
};

sub _description_for_defect {
    my ($self, $defect, $service) = @_;

    my $desc = 'Defect type: ' . $service->service_name;

    if ( $defect->{targetDate} ) {
        my ($date) = split('T', $defect->{targetDate});
        $desc .= "\nTarget completion date: $date";
    }

    $desc = $self->_defect_attributes_description($defect, $desc);

    return $desc;
}

sub _defect_attributes_description {
    my ($self, $defect, $desc) = @_;

    my $integ = $self->get_integration;
    my $mapping = $integ->config->{defect_attributes};

    return $desc unless $mapping;

    try {
        my $res = $integ->json_web_api_call("/defects/" . $defect->{defectNumber});
        foreach my $attr (@{ $res->{attributes} }) {
            my $k = $attr->{type}->{key};
            if (my $c = $mapping->{$k}) {
                my $name = $c->{name} || $attr->{name};
                my $value = $c->{numeric} ? $attr->{numericValue} : $c->{values}->{$attr->{pickValue}->{key}};
                $value ||= $attr->{currentValue};
                $desc .= "\n$name: $value";
            }
        }
    };

    return $desc;
}

1;
