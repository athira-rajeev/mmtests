# MonitorTurbostat.pm
package MMTests::MonitorTurbostat;
use MMTests::Monitor;
use VMR::Stat;
our @ISA = qw(MMTests::Monitor);
use strict;

sub new() {
	my $class = shift;
	my $self = {
		_ModuleName    => "MonitorTurbostat",
		_DataType      => MMTests::Monitor::MONITOR_PERFTIMESTAT,
		_ResultData    => []
	};
	bless $self, $class;
	return $self;
}

my %_colMap;
my @fieldHeaders;

sub printDataType() {
	my ($self) = @_;
	print "Busy,Time,Busy";
}

sub printPlot() {
	my ($self) = @_;
	$self->{_PrintHandler}->printRow($self->{_ResultData}, $self->{_FieldLength}, $self->{_FieldFormat});
}

sub extractSummary() {
	my ($self, $subheading) = @_;
	my @data = @{$self->{_ResultData}};

	my $fieldLength = 18;
	$self->{_SummaryHeaders} = [ "Statistic", "Mean", "Max" ];
	$self->{_FieldFormat} = [ "%${fieldLength}s", "%${fieldLength}.2f", ];

	# Array of potential headers and the samples
	my @headerCounters;
	my $index = 1;
	$headerCounters[0] = [];
	foreach my $header (@fieldHeaders) {
		next if $index == 0;
		$headerCounters[$index] = [];
		$index++;
	}

	# Collect the samples
	foreach my $rowRef (@data) {
		my @row = @{$rowRef};

		$index = 1;
		foreach my $header (@fieldHeaders) {
			next if $index == 0;
			push @{$headerCounters[$index]}, $row[$index];
			$index++;
		}
	}

	# Summarise
	$index = 1;
	foreach my $header (@fieldHeaders) {
		push @{$self->{_SummaryData}}, [ "$header",
			 calc_mean(@{@headerCounters[$index]}), calc_max(@{@headerCounters[$index]}) ];

		$index++;
	}

	return 1;
}

sub extractReport($$$$) {
	my ($self, $reportDir, $testName, $testBenchmark, $subHeading, $rowOrientated) = @_;
	my $timestamp;
	my $start_timestamp = 0;

	# Discover column header names
	my $file = "$reportDir/turbostat-$testName-$testBenchmark";
	if (scalar keys %_colMap == 0) {
		if (-e $file) {
			open(INPUT, $file) || die("Failed to open $file: $!\n");
		} else {
			$file .= ".gz";
			open(INPUT, "gunzip -c $file|") || die("Failed to open $file: $!\n");
		}
		while (!eof(INPUT)) {
			my $line = <INPUT>;
			next if ($line !~ /\s+Core\s+CPU/);
			$line =~ s/^\s+//;
			my @elements = split(/\s+/, $line);

			my $index;
			foreach my $header (@elements) {
				if ($header =~ /CPU%c[0-9]/ || $header eq "CorWatt" || $header eq "PkgWatt" || $header eq "%Busy") {
					$_colMap{$header} = $index;
				}

				$index++;
			}
			last;
		}
		close(INPUT);
		@fieldHeaders = sort keys %_colMap;
	}

	# Fill in the headers
	if ($subHeading ne "") {
		$self->{_FieldHeaders}  = [ "", "$subHeading" ];
		if (!defined $_colMap{$subHeading}) {
			die("Unrecognised heading $subHeading");
		}
		my $headingIndex = $_colMap{$subHeading};
		$self->{_HeadingIndex} = $_colMap{$subHeading};
		$self->{_HeadingName} = $subHeading;
	} else {
		$self->{_FieldHeaders}  = \@fieldHeaders;
	}

	# Read all counters
	if (-e $file) {
		open(INPUT, $file) || die("Failed to open $file: $!\n");
	} else {
		$file .= ".gz";
		open(INPUT, "gunzip -c $file|") || die("Failed to open $file: $!\n");
	}
	my $reading = 0;
	my $timestamp;
	my $start_timestamp = 0;
	my @row;
	while (!eof(INPUT)) {
		my $line = <INPUT>;

		$line =~ s/^\s+//;
		my @elements = split(/\s+/, $line);

		if ($line =~ /Core\s+CPU/) {
			if ($start_timestamp) {
				push @{$self->{_ResultData}}, [ @row ];
				$#row = -1;
			}

			$reading = 0;
			$timestamp = $elements[0];
			if ($start_timestamp == 0) {
				$start_timestamp = $elements[0];
			}
			push @row, $elements[0] - $start_timestamp;
		}

		if ($line =~ /Core\s+CPU/) {
			$reading = 1;
			next;
		}
		next if $reading != 1;
		next if @elements[4] ne "-" && @elements[4] ne "-";

		foreach my $header (@fieldHeaders) {
			next if ($header eq "Time");
			if ($subHeading eq "" || $header eq $subHeading) {
				push @row, $elements[$_colMap{$header}];
			}
		}
	}
	close(INPUT);
}

1;
