package LendingClub::Note;

use 5.010000;
use strict;
use warnings;
use WWW::Mechanize;
use LendingClub::Loan;
use LendingClub::Member;

our $VERSION = '0.01';

sub new
{
  my $package = shift;
  
  my $passed_params = shift;
  my %params = ();
  
  while ( my($key,$value) = each %{$passed_params} ) {
    if ( exists $params{$key} ) {
        $params{$key} = $value;
    }
    else {
        $params{$key} = $value;
    }
  }
  
  my $self = bless({}, $package);
  
  my $self->{'loan'} = LendingClub::Loan->new({lendingclub => $self, mech => $self->{'mech'}});
  my $self->{'member'} = LendingClub::Loan->new({lendingclub => $self, mech => $self->{'mech'}});
  
  return $self;
}

sub get_data
{
  my $self = shift;
  
  my $noteid = $self->{'noteid'};
  
  if (! $self->{'lendingclub'}->{'is_logged_in'})
  {
    $self->{'lendingclub'}->debug("Detected as not logged in.");
    $self->{'lendingclub'}->login();
  }
  
  $self->{'lendingclub'}->debug("Getting note data for note ID " . $noteid);
  
  my $mech = $self->{'mech'};
  $mech->get( "https://www.lendingclub.com/browse/loanDetail.action?loan_id=" . $noteid );
  my $htmlver = $mech->content( );
  
  my $note = {};
  #### TODO: SPLIT THIS OUT INTO SEPARATE SUB-MODULES (FOR LOAN, MEMBER, AND CREDIT HISTORY?)
  
  #### FIRST, GET THE LOAN DETAILS ####
  $self->{'loan'}->parse_loandetail($htmlver);
  
  #### THEN, GET THE MEMBER INFO ####
  $note->{'member'}->{'home_ownership'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Home\s+Ownership\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'current_employer'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Current\s+Employer\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'length_of_employment'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Length\s+of\s+Employment\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'gross_income'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Gross\s+Income\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'debt_to_income_pct'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Debt-to-Income\s+\(DTI\)\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'location'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Location\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'name'}->{'value'} = $1 if ($htmlver =~ m!>(.*?)\'s\s+Profile</td>!is);
  
  #### ADD VERIFIED INFORMATION ####
  $note->{'member'}->{'home_ownership'}->{'verified'} = $self->check_verified($note->{'member'}->{'home_ownership'}->{'value'});
  $note->{'member'}->{'current_employer'}->{'verified'} = $self->check_verified($note->{'member'}->{'current_employer'}->{'value'});
  $note->{'member'}->{'length_of_employment'}->{'verified'} = $self->check_verified($note->{'member'}->{'length_of_employment'}->{'value'});
  $note->{'member'}->{'gross_income'}->{'verified'} = $self->check_verified($note->{'member'}->{'gross_income'}->{'value'});
  $note->{'member'}->{'debt_to_income_pct'}->{'verified'} = $self->check_verified($note->{'member'}->{'debt_to_income_pct'}->{'value'});
  $note->{'member'}->{'location'}->{'verified'} = $self->check_verified($note->{'member'}->{'location'}->{'value'});
  
  #### THEN, GET THE CREDIT HISTORY ####
  $note->{'member'}->{'credit_score_range'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Credit\s+Score\s+Range\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'earliest_credit_line'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Earliest\s+Credit\s+Line\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'open_credit_lines'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Open\s+Credit\s+Lines\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'total_credit_lines'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Total\s+Credit\s+Lines\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'revolving_credit_balance'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Revolving\s+Credit\s+Balance\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'revolving_credit_utilization_pct'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Revolving\s+Line\s+Utilization\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'recent_inquiries'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Inquiries\s+in\s+the\s+Last\s+6\s+Months\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'delinquent_accounts'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Accounts\s+Now\s+Delinquent\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'delinquent_amount'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Delinquent\s+Amount\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'recent_delinquencies'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Delinquencies\s+\(Last\s+2\s+yrs\)\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'last_delinquency_months_elapsed'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Months\s+Since\s+Last\s+Delinquency\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'public_records_count'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Public\s+Records\s+On\s+File\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'member'}->{'last_public_record_months_elapsed'}->{'value'} = $1 if ($htmlver =~ m!<th\s*>\s*Months\s+Since\s+Last\s+Record\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  
  #### PULL IN ANY INFORMATION FROM A PREVIOUS get_invested_notes() CALL ####
  if ($self->{'notes_invested_received_csv'})
  {
    my @rows = @{ $self->{'notes_invested_rows'} };
    foreach my $row (@rows)
    {
      if ($row->{'NoteId'} == $noteid)
      {
        $note->{'loan'}->{'is_invested'} = 1;
        $note->{'loan'}->{'amount_lent'} += $row->{'AmountLent'};
        $note->{'loan'}->{'remaining_principal'} += $row->{'PrincipalRemaining'};
        $note->{'loan'}->{'payments_received'} += $row->{'PaymentsReceivedToDate'};
        $note->{'loan'}->{'next_payment_date'} = $row->{'NextPaymentDate'};
        $note->{'loan'}->{'next_payment_date'} = 'N/A' if ($note->{'loan'}->{'next_payment_date'} eq '' || $note->{'loan'}->{'next_payment_date'} eq 'null');
        $note->{'loan'}->{'in_portfolio_names'} .= ($row->{'PortfolioName'} . ',');
        $note->{'loan'}->{'in_portfolio_ids'} .= ($row->{'PortfolioId'} . ',');
      }
    }
    if ($note->{'loan'}->{'is_invested'})
    {
      chop($note->{'loan'}->{'in_portfolio_ids'});
      chop($note->{'loan'}->{'in_portfolio_names'});
    }
  }
  
  #### PULL IN ANY INFORMATION FROM A PREVIOUS get_available_notes() CALL ####
  if ($self->{'notes_available_received_csv'})
  {
    my @rows = @{ $self->{'notes_available_rows'} };
    foreach my $row (@rows)
    {
      if ($row->{'Id'} == $noteid)
      {
        $note->{'member'}->{'job_title'} = $row->{'JobTitle'};
        $note->{'member'}->{'job_title'} = 'N/A' if ($note->{'member'}->{'job_title'} eq '' || $note->{'member'}->{'job_title'} eq 'null');
        $note->{'member'}->{'employment_status'} = $row->{'EmpStatus'};
        $note->{'member'}->{'employment_status'} = 'N/A' if ($note->{'member'}->{'employment_status'} eq '' || $note->{'member'}->{'employment_status'} eq 'null');
        $note->{'member'}->{'gross_income'}->{'verification_status'} = $row->{'IncomeVStatus'};
        $note->{'member'}->{'gross_income'}->{'verification_status'} = 'N/A' if ($row->{'IncomeVStatus'} eq '' || $row->{'IncomeVStatus'} eq 'null');
      }
    }
  }
  
  #### THEN, FORMAT EACH OF THESE PIECES OF INFORMATION ####
  
  if ($note->{'member'}->{'length_of_employment'}->{'value'} =~ m!\<!i)
  {
    $note->{'member'}->{'length_of_employment'}->{'value'} = 'N/A';
  }
  else
  {
    $note->{'member'}->{'length_of_employment'}->{'value'} = $self->format_numeric($note->{'member'}->{'length_of_employment'}->{'value'});
    if ($note->{'member'}->{'length_of_employment'}->{'value'} ne 'N/A')
    {
      $note->{'member'}->{'length_of_employment'}->{'value'} *= 12;
    }
  }
  
  $note->{'member'}->{'gross_income'}->{'value'} = $self->format_dollar_amount($note->{'member'}->{'gross_income'}->{'value'});
  $note->{'member'}->{'debt_to_income_pct'}->{'value'} = $self->format_percentage($note->{'member'}->{'debt_to_income_pct'}->{'value'});
  $note->{'member'}->{'open_credit_lines'}->{'value'} = $self->format_numeric($note->{'member'}->{'open_credit_lines'}->{'value'});
  $note->{'member'}->{'total_credit_lines'}->{'value'} = $self->format_numeric($note->{'member'}->{'total_credit_lines'}->{'value'});
  $note->{'member'}->{'revolving_credit_balance'}->{'value'} = $self->format_dollar_amount($note->{'member'}->{'revolving_credit_balance'}->{'value'});
  $note->{'member'}->{'revolving_credit_utilization_pct'}->{'value'} = $self->format_percentage($note->{'member'}->{'revolving_credit_utilization_pct'}->{'value'});
  $note->{'member'}->{'delinquent_amount'}->{'value'} = $self->format_dollar_amount($note->{'member'}->{'delinquent_amount'}->{'value'});
  
  $note->{'member'}->{'recent_inquiries'}->{'value'} = $self->format_numeric($note->{'member'}->{'recent_inquiries'}->{'value'});
  $note->{'member'}->{'delinquent_accounts'}->{'value'} = $self->format_numeric($note->{'member'}->{'delinquent_accounts'}->{'value'});
  $note->{'member'}->{'recent_delinquencies'}->{'value'} = $self->format_numeric($note->{'member'}->{'recent_delinquencies'}->{'value'});
  $note->{'member'}->{'last_delinquency_months_elapsed'}->{'value'} = $self->format_numeric($note->{'member'}->{'last_delinquency_months_elapsed'}->{'value'});
  $note->{'member'}->{'public_records_count'}->{'value'} = $self->format_numeric($note->{'member'}->{'public_records_count'}->{'value'});
  $note->{'member'}->{'last_public_record_months_elapsed'}->{'value'} = $self->format_numeric($note->{'member'}->{'last_public_record_months_elapsed'}->{'value'});
  
  return $note;
}