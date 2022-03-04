package Open311::Endpoint::Integration::UK::Lincolnshire;

use Moo;
extends 'Open311::Endpoint::Integration::Confirm';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'lincolnshire_confirm';
    return $class->$orig(%args);
};

sub process_service_request_args {
    my $self = shift;
    my $args = $self->SUPER::process_service_request_args(shift);

    $args->{attributes}->{ACCU} = 'BG' if defined $args->{attributes}->{ACCU};
    $args->{attributes}->{PICL} = 'N' if defined $args->{attributes}->{PICL};

    # Lincolnshire have a slightly different mapping of FMS fields to Confirm fields.
    $args->{notes} = $args->{location};
    $args->{location} = $args->{attributes}->{closest_address};
    delete $args->{attributes}->{closest_address} if defined $args->{attributes}->{closest_address};

    return $args;
}

sub photo_filter {
    my ($self, $doc) = @_;
    return $doc->{fileName} =~ /jpe?g/i && $doc->{documentNotes} =~ /after/i;
}

1;
