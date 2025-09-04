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

    my $attribs = $self->_defect_attributes_description($defect);

    my $target = '';
    if ( $defect->{targetDate} ) {
        my ($date) = split('T', $defect->{targetDate});
        $target = "To be completed by: $date";
    }


    return <<DESC;
We've recorded a defect at this location following a statutory inspection and evaluated the risk it poses.

This risk level determines our target response time which are then are used to prioritise and programme work.

This defect has been assessed as:

$target
$attribs

Please be aware that this is the latest date we plan to have a repair completed by but may change as competing priorities and resources allow.

When works are due to take place we will let you know.
DESC
}

sub _defect_attributes_description {
    my ($self, $defect) = @_;

    my $integ = $self->get_integration;
    my $mapping = $integ->config->{defect_attributes};

    return '' unless $mapping;

    my $desc = '';
    try {
        my $res = $integ->json_web_api_call("/defects/" . $defect->{defectNumber});
        foreach my $attr (@{ $res->{attributes} }) {
            my $k = $attr->{type}->{key};
            if (my $c = $mapping->{$k}) {
                my $name = $c->{name} || $attr->{name};
                my $value = $c->{numeric} ? $attr->{numericValue} : $c->{values}->{$attr->{pickValue}->{key}};
                $value ||= $attr->{currentValue};
                $desc .= "$name: $value\n";
            }
        }
    };

    return $desc;
}

# Use only the first photo.
# Assumes GraphQL has returned already returned the documents in order.
around graphql_photo_documents_filter => sub {
    my ($orig, $self, $args) = @_;
    my $filtered = $self->$orig($args);
    return $filtered ? $filtered[0] : $filtered;
}

1;
