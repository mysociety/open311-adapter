=head1 NAME

Open311::Endpoint::Integration::UK::Aberdeenshire - Aberdeenshire integration set-up

=head1 SYNOPSIS

Aberdeenshire has a Confirm integration.

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Aberdeenshire;

use Moo;
use DateTime::Format::W3CDTF;
use List::Util qw(reduce);

extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'aberdeenshire_confirm';
    return $class->$orig(%args);
};

=head2 _description_for_defect

We construct update text from the returned information, including the
target date and the attributes in the feature_attributes configuration.

=cut

sub _description_for_defect {
    my ($self, $defect, $service) = @_;

    my $attribs = $self->_defect_attributes_description($defect);

    my $target = '';
    if ( $defect->{targetDate} ) {
        my ($date) = DateTime::Format::W3CDTF->parse_datetime($defect->{targetDate})->dmy('/');
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
    my $desc = '';

    my $attributes = $self->_fetch_defect_web_api_attributes($defect);
    foreach my $attr (@$attributes) {
        my ($code, $name, $value) = @$attr;
        $desc .= "$name: $value\n";
    }

    my $mapping;
    if ( $mapping = $integ->config->{feature_attributes} ) {
        foreach my $k ( keys %$mapping ) {
            if ( my $val = $defect->{feature}->{"attribute_$k"}->{attributeValueCode} ) {
                my $c = $mapping->{$k};
                $val = $c->{values}->{$val} || $val;
                $desc .= $c->{name} . ": $val\n";
            }
        }
    }

    return $desc;
}

=head2 filter_photos_graphql

Aberdeenshire want us to return the first photo only.

=cut

around filter_photos_graphql => sub {
    my ($orig, $class, @photos) = @_;
    my @filtered = $class->$orig(@photos);
    return @filtered unless scalar @filtered > 1;
    return (reduce { $a->{Date} < $b->{Date} ? $a : $b } @filtered);
};

=head2 Extra attributes

We look for two extra attributes when fetching updates from Confirm.
update_extra_defect_attributes adds them to the GraphQL query,
and enquiry_update_extra_data puts them on the returned extras.

=cut

sub update_extra_defect_attributes {
    my ($self) = @_;
    return <<EOF;
      feature {
        attribute_CCAT {
          attributeValueCode
        }
        attribute_SPD {
          attributeValueCode
        }
      }
EOF
}

sub enquiry_update_extra_data {
    my ($self, $status_log, $extras) = @_;

    # There might be some feature attribute values we want too
    if ( my $featureCCAT = $status_log->{centralEnquiry}->{enquiryLink}->{defect}->{feature}->{attribute_CCAT}->{attributeValueCode} ) {
        $extras ||= {};
        $extras->{featureCCAT} = $featureCCAT;
    }

    if ( my $featureSPD = $status_log->{centralEnquiry}->{enquiryLink}->{defect}->{feature}->{attribute_SPD}->{attributeValueCode} ) {
        $extras ||= {};
        $extras->{featureSPD} = $featureSPD;
    }
}

1;
