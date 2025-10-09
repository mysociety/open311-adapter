=head1 NAME

Open311::Endpoint::Role::SLWP

=head1 DESCRIPTION

Special handling for Kingston/Sutton/Merton. This makes sure the right
payment options are chosen for garden/bulky.

=cut

package Open311::Endpoint::Role::SLWP;

use utf8;
use Moo::Role;

has cancel_actiontype_id => ( is => 'ro', default => 518 );

around check_for_data_value => sub {
    my ($orig, $class, $name, $args, $request, $parent_name) = @_;

    if ($args->{service_code} eq '3159') {
        return 1 if $name eq 'Renewal' && $args->{description} =~ /Garden Subscription - Renew/;
    }

    return $class->$orig($name, $args, $request, $parent_name);
};

around post_service_request_update => sub {
    my ($orig, $class, $args) = @_;
    return $class->$orig($args) unless $args->{description};

    if (my $amend = $args->{attributes}{amend_items}) {
        $class->amend_booking($args);
        $args->{actiontype_id} = 520; # Amend items
        $args->{datatype_id} = 0;
    }

    if (my $payments = $args->{attributes}{payments}) {
        my @data = split /\|/, $payments;
        my @payments;
        for (my $i=0; $i<@data; $i+=2) {
            push @payments, { ref => $data[$i], amount => $data[$i+1] }
        }
        $class->update_event_payment($args, \@payments);
    } elsif ($args->{description} =~ /Payment confirmed, reference (.*), amount (.*)/) {
        my ($ref, $amount) = ($1, $2);
        $class->update_event_payment($args, [ { ref => $ref, amount => $amount } ]);
    }

    if ($args->{description} =~ /Booking cancelled/ || $args->{attributes}{booking_cancelled}) {
        $args->{actiontype_id} = $class->cancel_actiontype_id;
        $args->{datatype_id} = 0;
    }

    my $result = $class->$orig($args);

    return $result;
};

1;
