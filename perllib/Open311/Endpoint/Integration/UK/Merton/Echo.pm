=head1 NAME

Open311::Endpoint::Integration::UK::Merton::Echo - Merton-specific Echo backend configuration

=head1 SYNOPSIS

Merton specifics for its Echo backend

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Merton::Echo;

use utf8;
use DateTime;
use Moo;
extends 'Open311::Endpoint::Integration::Echo';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'merton_echo';
    return $class->$orig(%args);
};

=head2 process_service_request_args

If we are sending an assisted collection event, we need to set some special
parameters.

=cut

around process_service_request_args => sub {
    my ($orig, $class, $args) = @_;
    my $request = $class->$orig($args);
    # Assisted collection
    if ($args->{service_code} eq "1565-add") {
        $args->{attributes}{"Add_to_Assist"} = 1;
    } elsif ($args->{service_code} eq "1565-remove") {
        $args->{attributes}{"Remove_from_Assist"} = 1;
    }
    return $request;
};

around check_for_data_value => sub {
    my ($orig, $class, $name, $args, $request, $parent_name) = @_;

    my $service = $args->{attributes}{service_id} || '';

    return 1 if $name eq 'Container Mix' && ($service eq '2241' || $service eq '2250' || $service eq '2246' || $service eq '3571');
    return 1 if $name eq 'Paper' && ($service eq '2240' || $service eq '2249' || $service eq '2632');
    return 1 if $name eq 'Food' && ($service eq '2239' || $service eq '2248');
    return 1 if $name eq 'Garden' && $service eq '2247';
    return 1 if $name eq 'Refuse Bag' && $service eq '2242';
    return 1 if $name eq 'Refuse Bin' && ($service eq '2238' || $service eq '2243' || $service eq '3576');

    # Garden waste
    if ($args->{service_code} eq '1638') {
        my $method = $args->{attributes}{LastPayMethod} || '';
        return 2 if $name eq 'Payment Type' && $method eq 3; # DD
        return 3 if $name eq 'Payment Type' && $method eq 4; # 'cheque' (or phone)
    }

    # Bulky items
    if ($args->{service_code} eq '1636') {
        # Default in configuration is Payment Type 1 (Card), Payment Method 2 (Website)
        my $method = $args->{attributes}{payment_method} || '';
        return 2 if $name eq 'Payment Type' && $method eq 'cheque'; # Cheque
        if ($name eq 'Payment Method') {
            return 1 if $method eq 'csc' || $method eq 'cheque'; # Borough Phone Payment
            return 2 if $method eq 'credit_card'; # Borough Website Payment
        }
    }

    return $class->$orig($name, $args, $request, $parent_name);
};

around post_service_request_update => sub {
    my ($orig, $class, $args) = @_;
    return $class->$orig($args) unless $args->{description};

    if ($args->{description} =~ /Payment confirmed, reference (.*), amount (.*)/) {
        my ($ref, $amount) = ($1, $2);
        $amount =~ s/£//;
        my $integ = $class->get_integration;
        my $event = $integ->GetEvent($args->{service_request_id});
        # Could GetEventType and loop through it all to find these IDs out but for just this seemed okay
        my $data = {
            id => 27409,
            childdata => [
                { id => 27410, value => $ref },
                { id => 27411, value => $amount },
            ],
        };
        $integ->UpdateEvent({ id => $event->{Id}, data => [ $data ] });
        $args->{description} = ''; # Blank out so nothing sent to Echo now
    }

    if ($args->{description} eq 'Booking cancelled by customer') {
        $args->{actiontype_id} = 8;
        $args->{datatype_id} = 0;
    }

    my $result = $class->$orig($args);

    return $result;
};

1;
