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
    my $filename_ok = $self->SUPER::photo_filter($doc);
    my $notes_ok = ($doc->{Notes} || '') =~ /after/i;
    return $filename_ok && $notes_ok;
}

# We have a number of Confirm service/subject codes that have more than one
# entry in FMS. We have a manual list of which FMS category to use in these
# cases. This depends on whether it's a category in more than one group, or
# one that is both wrapped and not, or one that is wrapped in two different
# categories, or one that's wrapped twice in the same category, or one that
# is two different categories...

sub munge_new_request {
    my ($self, $args, $services) = @_;

    my $sc = $args->{service}->service_code;
    my $osc = $args->{extras}->{original_service_code} || '';
    if ($sc eq 'HMOB_MO06' || $sc eq 'HMOB_MO05') {
        $args->{extras}->{group} = 'Roads and cycleways';
    } elsif ($sc eq 'SD_HSF9_2') {
        $args->{service} = $services->{TRIP_HAZARD};
        $args->{extras}->{original_service_code} = 'SD_HSF9';
        $args->{extras}->{group} = 'Pavement and verge';
    } elsif ($sc eq 'HMVG_MV05_2') {
        $args->{service} = $services->{HMVG_MV05_1};
    } elsif ($osc eq 'PRWD_RW41') {
        $args->{service} = $services->{PROW_TREES}; # in case it's PROW_OBS
    } elsif ($osc eq 'HMOB_MO02') {
        $args->{extras}->{original_service_code} = 'HMOB_MO02_2';
    } elsif ($osc eq 'HMOB_MO10') {
        $args->{extras}->{original_service_code} = 'HMOB_MO10_1';
    }
}

1;
