package Open311::Endpoint::Integration::UK::Gloucester;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';
with 'Role::Memcached';

use Encode;
use JSON::MaybeXS;
use Path::Tiny;
use FixMyStreet::WorkingDays;

around BUILDARGS => sub {
    my ( $orig, $class, %args ) = @_;
    $args{jurisdiction_id} = 'gloucester_alloy';
    return $class->$orig(%args);
};

has testing => ( is => 'ro', default => 0 );

sub process_attributes {
    my ($self, $args) = @_;

    my $group = $args->{attributes}{group};
    my $service_code = $args->{service_code_alloy};

    my $category_code
        = $group
        ? $self->config->{service_whitelist}{$group}{$service_code}
        : $self->config->{service_whitelist}{''}{$service_code};

    # Appends to attribute[description] before attributes processed below.
    # May return question attributes to be added to $attributes list.
    my @question_attributes = $self->_munge_question_args(
        $args,
        $category_code,
    );

    my $attributes = $self->SUPER::process_attributes($args);
    push @$attributes, @question_attributes if @question_attributes;

    $self->_populate_priority_and_target_date($attributes, $service_code);

    $self->_populate_category_and_group_attr(
        $attributes,
        $category_code,
    );

    return $attributes;
}

sub _munge_question_args {
    my ( $self, $args, $category_code ) = @_;

    my @q_attributes;

    if ( ref($category_code) eq 'HASH' ) {
        my $questions = $category_code->{questions};

        for my $q ( @$questions ) {
            my $code = $q->{code};
            my $q_text = $q->{description};
            my $answer = $args->{attributes}{$code};

            if ($answer) {
                $args->{attributes}{description} .= "\n\n$q_text\n$answer";

                if ( my $attr_code = $q->{alloy_attribute} ) {
                    my $answer_code
                        = $self->config->{question_mapping}{$attr_code}{$answer};

                    push @q_attributes, {
                        attributeCode => $attr_code,
                        value         => [$answer_code],
                    };
                }
            }
        }
    }

    return @q_attributes;
}

sub _populate_priority_and_target_date {
    my ($self, $attr, $category) = @_;
    my $mapping = $self->config->{category_attribute_mapping};

    # Priority
    my $priority_value = $self->config->{question_mapping}{priority}{$category};
    if ($priority_value) {
        # It has a default, so change that
        foreach (@$attr) {
            if ($_->{attributeCode} eq $mapping->{priority}) {
                $_->{value} = [$priority_value];
                last;
            }
        }
    }

    # Target date
    my $sla = $self->config->{question_mapping}{target_date_sla}{$category};
    die "No target date entry found for $category" unless $sla;
    my $date;
    my $formatter = DateTime::Format::W3CDTF->new(strict => 1);
    my $now = DateTime->now(time_zone => "Europe/London", formatter => $formatter);
    if ($sla->{days}) {
        my $wd = FixMyStreet::WorkingDays->new(public_holidays => $self->public_holidays());
        $date = $wd->add_days($now, $sla->{days});
    } elsif ($sla->{weeks}) {
        $date = $now->add(weeks => $sla->{weeks});
    }
    $date->set(hour => 23, minute => 59, second => 59)->set_time_zone('UTC');

    push @$attr, { attributeCode => $mapping->{target_date}, value => "$date" };
}

sub _populate_category_and_group_attr {
    my ( $self, $attr, $category_code ) = @_;

    if ( ref($category_code) eq 'HASH' ) {
        $category_code = $category_code->{alloy_code};
    }

    # NB FMS category == Alloy subcategory; FMS group == Alloy category

    my $mapping = $self->config->{category_attribute_mapping};

    push @$attr, {
        attributeCode => $mapping->{subcategory},
        value => [$category_code],
    };

    my $group_code
        = $self->config->{subcategory_id_to_category_id}{$category_code};
    die
        "No attributes_customerContactCategory code found for attributes_customerContactSubCategory $category_code"
        unless $group_code;

    push @$attr, {
        attributeCode => $mapping->{category},
        value => [$group_code],
    };

    my $srv_area_code
        = $self->config->{category_id_to_service_area_id}{$group_code}
        || $self->config->{category_id_to_service_area_id}{$category_code};
    die
        "No attributes_customerContactServiceArea code found for attributes_customerContactCategory $group_code or attributes_customerContactSubCategory $category_code"
        unless $srv_area_code;

    push @$attr, {
        attributeCode => $mapping->{service_area},
        value => [$srv_area_code],
    } if $srv_area_code;
}

=head2 _get_inspection_status

Determines the inspection status and external status code for a report.

1. Maps the internal status code to a human-readable status using the parent class method
2. If an external status code mapping is configured, fetches the status object itself
   from Alloy (e.g., the "cancelled" status object) and extracts the external status
   code from that status object's attributes, with 24-hour memcache to avoid repeated API requests
3. Returns both the mapped status and external status code

=cut

sub _get_inspection_status {
    my ($self, $attributes, $mapping) = @_;

    my $status = 'open';
    my $ext_code;
    if ($attributes->{$mapping->{status}}) {
        my $status_code = $attributes->{$mapping->{status}}->[0];
        $status = $self->inspection_status($status_code);

        if ($mapping->{external_status_code}) {
            my $cache_key = "alloy-item-$status_code";
            $ext_code = $self->memcache->get($cache_key);
            unless ($ext_code) {
                my $status_obj = $self->alloy->api_call(call => "item/$status_code");
                $status_obj = $status_obj->{item};
                my $status_attributes = $self->alloy->attributes_to_hash($status_obj);
                $ext_code = $status_attributes->{$mapping->{external_status_code}};
                $self->memcache->set($cache_key, $ext_code, 24 * 60 * 60); # 24 hours
            }
        }
    }
    return ($status, $ext_code);
}

# Bank Holidays (similar to FMS UK code)

sub public_holidays {
    my $self = shift;
    my $nation = 'england-and-wales';
    my $json = $self->_get_bank_holiday_json();
    return [ map { $_->{date} } @{$json->{$nation}{events}} ];
}

sub _get_bank_holiday_json {
    my $self = shift;
    my $file = 'bank-holidays.json';
    my $cache_file = path(__FILE__)->parent(7)->realpath->child("data/$file");
    my $js;
    # uncoverable branch true
    if (-s $cache_file && -M $cache_file <= 7 && !$self->testing) {
        # uncoverable statement
        $js = $cache_file->slurp_utf8;
    } else {
        $js = _fetch_url("https://www.gov.uk/$file");
        # uncoverable branch false
        $js = decode_utf8($js) if !utf8::is_utf8($js);
        # uncoverable branch true
        if ($js && !$self->testing) {
            # uncoverable statement
            $cache_file->spew_utf8($js);
        }
    }
    $js = JSON->new->decode($js) if $js;
    return $js;
}

sub _fetch_url {
    my $url = shift;
    my $ua = LWP::UserAgent->new;
    $ua->timeout(5);
    $ua->get($url)->content;
}

1;
