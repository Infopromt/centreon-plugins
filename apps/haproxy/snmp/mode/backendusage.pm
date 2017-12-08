#
# Copyright 2017 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package apps::haproxy::snmp::mode::backendusage;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);

my $instance_mode;

sub custom_status_threshold {
    my ($self, %options) = @_;
    my $status = 'ok';
    my $message;

    eval {
        local $SIG{__WARN__} = sub { $message = $_[0]; };
        local $SIG{__DIE__} = sub { $message = $_[0]; };

        if (defined($instance_mode->{option_results}->{critical_status}) && $instance_mode->{option_results}->{critical_status} ne '' &&
            eval "$instance_mode->{option_results}->{critical_status}") {
            $status = 'critical';
        } elsif (defined($instance_mode->{option_results}->{warning_status}) && $instance_mode->{option_results}->{warning_status} ne '' &&
                 eval "$instance_mode->{option_results}->{warning_status}") {
            $status = 'warning';
        }
    };
    if (defined($message)) {
        $self->{output}->output_add(long_msg => 'filter status issue: ' . $message);
    }

    return $status;
}

sub custom_status_output {
    my ($self, %options) = @_;

    my $msg = 'status : ' . $self->{result_values}->{status};
    return $msg;
}

sub custom_status_calc {
    my ($self, %options) = @_;

    $self->{result_values}->{status} = $options{new_datas}->{$self->{instance} . '_alBackendStatus'};
    $self->{result_values}->{display} = $options{new_datas}->{$self->{instance} . '_display'};
    return 0;
}

sub set_counters {
    my ($self, %options) = @_;
    
    $self->{maps_counters_type} = [
        { name => 'backend', type => 1, cb_prefix_output => 'prefix_backend_output', message_multiple => 'All backends are ok' },
    ];
    
    $self->{maps_counters}->{backend} = [
        { label => 'status', threshold => 0, set => {
                key_values => [ { name => 'alBackendStatus' }, { name => 'display' } ],
                closure_custom_calc => $self->can('custom_status_calc'),
                closure_custom_output => $self->can('custom_status_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => $self->can('custom_status_threshold'),
            }
        },
        { label => 'current-queue', set => {
                key_values => [ { name => 'alBackendQueueCur' }, { name => 'display' } ],
                output_template => 'Current queue : %s',
                perfdatas => [
                    { label => 'current_queue', value => 'alBackendQueueCur_absolute', template => '%s', 
                      min => 0, label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
        { label => 'current-sessions', set => {
                key_values => [ { name => 'alBackendSessionCur' }, { name => 'display' } ],
                output_template => 'Current sessions : %s',
                perfdatas => [
                    { label => 'current_sessions', value => 'alBackendSessionCur_absolute', template => '%s', 
                      min => 0, label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
        { label => 'total-sessions', set => {
                key_values => [ { name => 'alBackendSessionTotal', diff => 1 }, { name => 'display' } ],
                output_template => 'Total sessions : %s',
                perfdatas => [
                    { label => 'total_connections', value => 'alBackendSessionTotal_absolute', template => '%s', 
                      min => 0, label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
        { label => 'traffic-in', set => {
                key_values => [ { name => 'alBackendBytesIN', diff => 1 }, { name => 'display' } ],
                output_template => 'Traffic In : %s %s/s',
                per_second => 1, output_change_bytes => 2,
                perfdatas => [
                    { label => 'traffic_in', value => 'alBackendBytesIN_per_second', template => '%.2f', 
                      min => 0, unit => 'b/s', label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
        { label => 'traffic-out', set => {
                key_values => [ { name => 'alBackendBytesOUT', diff => 1 }, { name => 'display' } ],
                output_template => 'Traffic Out : %s %s/s',
                per_second => 1, output_change_bytes => 2,
                perfdatas => [
                    { label => 'traffic_out', value => 'alBackendBytesOUT_per_second', template => '%.2f', 
                      min => 0, unit => 'b/s', label_extra_instance => 1, instance_use => 'display_absolute' },
                ],
            }
        },
    ];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options, statefile => 1);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                { 
                                  "filter-name:s"           => { name => 'filter_name' },
                                  "warning-status:s"        => { name => 'warning_status', default => '' },
                                  "critical-status:s"       => { name => 'critical_status', default => '%{status} !~ /UP/i' },
                                });
    
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    $instance_mode = $self;
    $self->change_macros();
}

sub prefix_backend_output {
    my ($self, %options) = @_;

    return "Backend '" . $options{instance_value}->{display} . "' ";
}

sub change_macros {
    my ($self, %options) = @_;

    foreach (('warning_status', 'critical_status')) {
        if (defined($self->{option_results}->{$_})) {
            $self->{option_results}->{$_} =~ s/%\{(.*?)\}/\$self->{result_values}->{$1}/g;
        }
    }
}

my $mapping = {
    alBackendName           => { oid => '.1.3.6.1.4.1.23263.4.2.1.3.3.1.3' },
    alBackendQueueCur       => { oid => '.1.3.6.1.4.1.23263.4.2.1.3.3.1.4' },
    alBackendSessionCur     => { oid => '.1.3.6.1.4.1.23263.4.2.1.3.3.1.7' },
    alBackendSessionTotal   => { oid => '.1.3.6.1.4.1.23263.4.2.1.3.3.1.10' },
    alBackendBytesIN        => { oid => '.1.3.6.1.4.1.23263.4.2.1.3.3.1.12' },
    alBackendBytesOUT       => { oid => '.1.3.6.1.4.1.23263.4.2.1.3.3.1.13' },
    alBackendStatus         => { oid => '.1.3.6.1.4.1.23263.4.2.1.3.3.1.20' },
};

sub manage_selection {
    my ($self, %options) = @_;

    if ($options{snmp}->is_snmpv1()) {
        $self->{output}->add_option_msg(short_msg => "Need to use SNMP v2c or v3.");
        $self->{output}->option_exit();
    }
    
    $self->{backend} = {};
    my $snmp_result = $options{snmp}->get_multiple_table(
        oids => [
            { oid => $mapping->{alBackendName}->{oid} },
            { oid => $mapping->{alBackendQueueCur}->{oid} },
            { oid => $mapping->{alBackendSessionCur}->{oid} },
            { oid => $mapping->{alBackendSessionTotal}->{oid} },
            { oid => $mapping->{alBackendBytesIN}->{oid} },
            { oid => $mapping->{alBackendBytesOUT}->{oid} },
            { oid => $mapping->{alBackendStatus}->{oid} },
        ],
        return_type => 1, nothing_quit => 1);

    foreach my $oid (keys %{$snmp_result}) {
        next if ($oid !~ /^$mapping->{alBackendName}->{oid}\.(.*)$/);
        my $instance = $1;
        my $result = $options{snmp}->map_instance(mapping => $mapping, results => $snmp_result, instance => $instance);

        if (defined($self->{option_results}->{filter_name}) && $self->{option_results}->{filter_name} ne '' &&
            $result->{alBackendName} !~ /$self->{option_results}->{filter_name}/) {
            $self->{output}->output_add(long_msg => "skipping '" . $result->{wgPolicyName} . "': no matching filter.", debug => 1);
            next;
        }
        
        $result->{alBackendBytesIN} *= 8;
        $result->{alBackendBytesOUT} *= 8;
        $self->{backend}->{$instance} = { display => $result->{alBackendName}, 
            %$result
        };
    }
    
    if (scalar(keys %{$self->{backend}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "No backend found.");
        $self->{output}->option_exit();
    }
    
    $self->{cache_name} = "haproxy_" . $self->{mode} . '_' . $options{snmp}->get_hostname()  . '_' . $options{snmp}->get_port() . '_' .
        (defined($self->{option_results}->{filter_counters}) ? md5_hex($self->{option_results}->{filter_counters}) : md5_hex('all')) . '_' .
        (defined($self->{option_results}->{filter_name}) ? md5_hex($self->{option_results}->{filter_name}) : md5_hex('all'));
}

1;

__END__

=head1 MODE

Check backend usage.

=over 8

=item B<--filter-counters>

Only display some counters (regexp can be used).
Example: --filter-counters='^total-sessions$'

=item B<--filter-name>

Filter backend name (can be a regexp).

=item B<--warning-status>

Set warning threshold for status.
Can used special variables like: %{status}, %{display}

=item B<--critical-status>

Set critical threshold for status (Default: '%{status} !~ /UP/i').
Can used special variables like: %{status}, %{display}

=item B<--warning-*>

Threshold warning.
Can be: 'total-sessions', 'current-sessions', 'current-queue',
'traffic-in' (b/s), 'traffic-out' (b/s).

=item B<--critical-*>

Threshold critical.
Can be: 'total-sessions', 'current-sessions', 'current-queue',
'traffic-in' (b/s), 'traffic-out' (b/s).

=back

=cut
