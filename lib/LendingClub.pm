package LendingClub;

use 5.010000;
use strict;
use warnings;
use WWW::Mechanize;
use Text::CSV;
use XML::Simple;
use HTTP::Request;
use JSON;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use LendingClub ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

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
  
  $self->{'username'} = $params{'username'};
  $self->{'password'} = $params{'password'};
  $self->{'debug'} = $params{'debug'};
  $self->{'portfolio_name'} = $params{'portfolio_name'} ? $params{'portfolio_name'} : 'Robopicks';
  
  if ($self->{'debug'})
  {
    print "Debug logging enabled.\n";
  }
  
  my $mech;
  if ($params{'noproxy'})
  {
    if ($self->{'debug'})
    {
      print "Disabling proxy.\n";
    }
    $mech = WWW::Mechanize->new(noproxy => 1);
  }
  else
  {
    $mech = WWW::Mechanize->new();
  }
  $mech->agent_alias( 'Windows IE 6' );
  
  $self->{'mech'} = $mech;
  
  return $self;
}

sub get_location_info
{
  my $self = shift;
  my $city = shift;
  my $state = shift;
  my $citytype = 1;
  
  if ($city =~ /\,/ && (! $state || $state eq ''))
  {
    $self->debug("City and state came together... attempting to split");
    ($city,$state) = split(/\s*\,\s*/,$city);
  }
  elsif ($city !~ /\,/ && (! $state || $state eq ''))
  {
    $self->debug("Only state defined");
    $citytype = 0;
    $state = $city;
  }
  $self->debug("Gathering city data for CITY = $city / STATE = $state");
  
  my $mech = $self->{'mech'};
  my $url;
  if ($citytype)
  {
    $url = 'http://www.fizber.com/xml_data/xml_neighborhood_info.xml?type=city&amp;state=' . $state . '&amp;city=' . $city;
  }
  else
  {
    $url = 'http://www.fizber.com/xml_data/xml_neighborhood_info.xml?type=state&amp;state=' . $state;
  }
  $mech->get( $url );
  my $xmlver = $mech->content( );
  
  my $xmlstruct = XMLin($xmlver, ForceArray => 1);
  return $xmlstruct;
}

sub invest
{
  my $self = shift;
  my $noteid = shift;
  my $amount = shift;
  my $portfolioname = shift;
  
  my $url = 'https://www.lendingclub.com/browse/addToPortfolio.action?loan_id=' . $noteid . '&loan_amount=' . $amount;
  
  my $mech = $self->{'mech'};
  $mech->get( $url );
  my $txtcontent = $mech->content( );
  $mech->get( 'https://www.lendingclub.com/portfolio/viewOrder.action' );
  $txtcontent = $mech->content( );
  $mech->get( 'https://www.lendingclub.com/portfolio/placeOrder.action' );
  $txtcontent = $mech->content( );
  
  my $i = 0;
  foreach my $f ( @{ $mech->forms() } )
  {
    my $input = $f->find_input( 'place-order-link1' , 'submit' );
    last if (defined($input));
    $i++;
  }
  $i--;
  
  if ($i > -1)
  {
    $mech->submit_form(
      form_number => $i
    );
    
    $txtcontent = $mech->content( );
    
    if ($portfolioname)
    {
      #this part fails ...
      my $j = 0;
      my $formnum = -1;
      my $portfolioexists = 0;
      foreach my $fm ( $mech->forms() )
      {
        foreach my $inp ( $fm->inputs )
        {
          print $inp->class . ' = ' . $inp->id . ' = ' . $inp->value . "\n";
          if ( lc($inp->type) eq 'option' && lc($inp->value) eq lc($portfolioname) )
          {
            $portfolioname = $inp->value;
            $portfolioexists = 1;
          }
          elsif ( lc($inp->type) eq 'option' && lc($inp->class) eq 'new_portfolio' )
          {
            $formnum = $j;
          }
        }
        $j++;
      }
      if ($formnum > -1)
      {
        $txtcontent = $mech->content( );
        if ($txtcontent =~ m!name="order_id"\s+value="(.*?)"!is)
        {
          my $orderid = $1;
          my $request = HTTP::Request->new(POST => 'https://www.lendingclub.com/data/portfolioManagement');
          $request->content_type('application/x-www-form-urlencoded');
          my $portfolionameencoded = $portfolioname;
          $portfolionameencoded =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
          my $post = 'lcportfolio_description=&record_id=1&lcportfolio_name=' . $portfolionameencoded . '&loan_id=' . $noteid . '&order_id=' . $orderid;
          $post .= ($portfolioexists ? '&method=addToLCPortfolio' : '&method=createLCPortfolio');
          $request->content($post);
          $mech->request($request);
        }
      }
    }
  }
}

sub get_note_data
{
  my $self = shift;
  my $noteid = shift;
  
  if (! $self->{'is_logged_in'})
  {
    $self->debug("Detected as not logged in.");
    $self->login();
  }
  
  $self->debug("Getting note data for note ID " . $noteid);
  
  my $mech = $self->{'mech'};
  $mech->get( "https://www.lendingclub.com/browse/loanDetail.action?loan_id=" . $noteid );
  my $htmlver = $mech->content( );
  
  my $note = {};
  #### TODO: SPLIT THIS OUT INTO SEPARATE SUB-MODULES (FOR LOAN, MEMBER, AND CREDIT HISTORY?)
  
  #### FIRST, GET THE LOAN DETAILS ####
  $note->{'loan'}->{'amount_requested'} = $1 if ($htmlver =~ m!<th\s*>\s*Amount\s+Requested\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'loan'}->{'loan_purpose'} = $1 if ($htmlver =~ m!<th\s*>\s*Loan\s+Purpose\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'loan'}->{'loan_grade'} = $1 if ($htmlver =~ m!<th\s*>\s*Loan\s+Grade\s*</th>\s*<td[^\.]*?>\s*<span[^\.]*?>\s*(.*?)\s*</span>\s*</td>!is);
  $note->{'loan'}->{'interest_rate'} = $1 if ($htmlver =~ m!<th\s*>\s*Interest\s+Rate\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'loan'}->{'monthly_payment'} = $1 if ($htmlver =~ m!<th\s*>\s*Monthly\s+Payment\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'loan'}->{'loan_length'} = $1 if ($htmlver =~ m!<th\s*>\s*Loan\s+Length\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'loan'}->{'funding_received'} = $1 if ($htmlver =~ m!<th\s*>\s*Funding\s+Received\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'loan'}->{'num_investors'} = $1 if ($htmlver =~ m!<th\s*>\s*Investors\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'loan'}->{'loan_status'} = $1 if ($htmlver =~ m!<th\s*>\s*Loan\s+Status\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'loan'}->{'loan_submitted_date_time'} = $1 if ($htmlver =~ m!<th\s*>\s*Loan\s+Submitted\s+on\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'loan'}->{'title'} = $1 if ($htmlver =~ m!<h1>\s*(.*?)</h1>!is);
  $note->{'loan'}->{'credit_review_status'} = $1 if ($htmlver =~ m!<th\s*>\s*Credit\s+Review\s+Status\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'loan'}->{'listing_expires_in'} = $1 if ($htmlver =~ m!<th\s*>\s*Listing\s+Expires\s+In\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $note->{'loan'}->{'description'} = $1 if ($htmlver =~ m!<div\s+class="scrub"\s+id="loan_description">\s*(.*?)\s*</div>!is);
  
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
  $note->{'loan'}->{'amount_requested'} = $self->format_dollar_amount($note->{'loan'}->{'amount_requested'});
  $note->{'loan'}->{'interest_rate'} = $self->format_percentage($note->{'loan'}->{'interest_rate'});
  $note->{'loan'}->{'monthly_payment'} = $self->format_dollar_amount($note->{'loan'}->{'monthly_payment'});
  $note->{'loan'}->{'num_investors'} = $self->format_numeric($note->{'loan'}->{'num_investors'});
  if ($note->{'loan'}->{'loan_length'} =~ m!(\d+)\s+year[s]*!i)
  {
    $note->{'loan'}->{'loan_length'} = (int($1) * 12);
  }
  elsif ($note->{'loan'}->{'loan_length'} =~ m!(\d+)\s+month[s]*!i)
  {
    $note->{'loan'}->{'loan_length'} = int($1);
  }
  else
  {
    $note->{'loan'}->{'loan_length'} = 'N/A';
  }
  
  if ($note->{'loan'}->{'funding_received'} =~ m!([\$\d\,\.]*)\s+\(([\%\d\,\.]*)\s+funded\)!)
  {
    $note->{'loan'}->{'funding_received_amt'} = $self->format_dollar_amount($1);
    $note->{'loan'}->{'funding_received_pct'} = $self->format_percentage($2);
  }
  
  if ($note->{'loan'}->{'credit_review_status'})
  {
    $note->{'loan'}->{'credit_review_status'} =~ s/<[^>]*?>//g;
    $note->{'loan'}->{'credit_review_status'} =~ s/\&nbsp;//g;
    $note->{'loan'}->{'credit_review_status'} =~ s/^\s*//g;
    $note->{'loan'}->{'credit_review_status'} =~ s/\s*$//g;
  }
  
  if ($note->{'loan'}->{'listing_expires_in'})
  {
    $note->{'loan'}->{'listing_expires_in'} =~ s/\(.*?\)//;
    my $hr = $1 if ($note->{'loan'}->{'listing_expires_in'} =~ m!(\d+)h!i);
    my $mn = $1 if ($note->{'loan'}->{'listing_expires_in'} =~ m!(\d+)m!i);
    my $da = $1 if ($note->{'loan'}->{'listing_expires_in'} =~ m!(\d+)d!i);
    if ($hr || $mn || $da)
    {
      $mn = 0 if (! $mn);
      $da = 0 if (! $da);
      $hr = 0 if (! $hr);
      $note->{'loan'}->{'listing_expires_in'} = $mn + $hr * 60 + $da * 1440;
    }
  }
  
  $note->{'loan'}->{'description'} =~ s/<.*?>//g;
  
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

sub debug
{
  my $self = shift;
  my $msg = shift;
  
  if ($self->{'debug'})
  {
    print $msg . "\n";
  }
}

sub parse_questions_answers
{
  my $self = shift;
  my $html = shift;
  
  
}

sub calc_statistics_from_notes
{
  my $self = shift;
  
  my @rows = $self->{'notes_invested_rows'};
  my $columns = $self->{'notes_invested_rows_headers'};
  
  if (! $self->{'notes_invested_received_csv'})
  {
    $self->debug("Have not yet received notes aggregation.");
    $self->get_invested_notes();
  }
  
  my %toreturn = ();
  $toreturn{'portfolios_count'} = $self->{'notes_porfolios'};
  $toreturn{'loanlength_count'} = $self->{'notes_loanlength'};
  $toreturn{'status_count'} = $self->{'notes_porfolios'};
}

sub get_available_notes
{
  my $self = shift;
  
  if (! $self->{'is_logged_in'})
  {
    $self->debug("Detected as not logged in.");
    $self->login();
  }
  
  $self->debug("Getting notes summary");
  
  my $mech = $self->{'mech'};
  $mech->get( "https://www.lendingclub.com/browse/browseNotesRawData.action" );
  
  $mech->save_content( 'notes_avail.csv' );
  
  my $csv = Text::CSV->new ( { binary => 1 } ) or die "Cannot use CSV: ".Text::CSV->error_diag ();
  
  my @rows = ();
  my @row_id_array = ();
  open my $fh, "<:encoding(utf8)", "notes_avail.csv" or die "notes_avail.csv: $!";
  my $first_row = 0;
  
  my $row = $csv->getline( $fh );
  $csv->column_names($row);
  my $columns = $row;
  while ( my $row = $csv->getline_hr( $fh ) )
  {
    push @rows, $row;
    push @row_id_array, $row->{'NoteId'};
  }
  
  $csv->eof or $csv->error_diag();
  close $fh;
  
  $self->debug("Total of " . $#rows . " notes received");
  
  $self->{'notes_available_rows'} = \@rows;
  $self->{'notes_available_rows_headers'} = $columns;
  $self->{'notes_available_received_csv'} = 1;
  
  if (! $self->{'debug'})
  {
    unlink( 'notes_avail.csv' );
  }
  
  return @row_id_array;
}

sub get_invested_notes
{
  my $self = shift;
  
  if (! $self->{'is_logged_in'})
  {
    $self->debug("Detected as not logged in.");
    $self->login();
  }
  
  $self->debug("Getting notes summary");
  
  my $mech = $self->{'mech'};
  $mech->get( "https://www.lendingclub.com/account/notesRawData.action" );
  
  $mech->save_content( 'notes_invested.csv' );
  
  my $csv = Text::CSV->new ( { binary => 1 } ) or die "Cannot use CSV: ".Text::CSV->error_diag ();
  
  my @rows = ();
  my @row_id_array = ();
  open my $fh, "<:encoding(utf8)", "notes_invested.csv" or die "notes_invested.csv: $!";
  my $first_row = 0;
  
  my %portfolios_hash = ();
  my %loanlength_hash = ();
  my %status_hash = ();
  my %portfolios_accrued_hash = ();
  my %loanlength_accrued_hash = ();
  my %status_accrued_hash = ();
  
  my $row = $csv->getline( $fh );
  $csv->column_names($row);
  my $columns = $row;
  while ( my $row = $csv->getline_hr( $fh ) )
  {
    push @rows, $row;
    push @row_id_array, $row->{'NoteId'};
    
    my $expected_per_payment = $row->{'AmountLent'} * (1 + $row->{'InterestRate'}) / $row->{'LoanMaturity.Maturity'};
    
    $portfolios_hash{$row->{'PortfolioName'}} = 0 if (! $portfolios_hash{$row->{'PortfolioName'}});
    $loanlength_hash{$row->{'LoanMaturity.Maturity'}} = 0 if (! $loanlength_hash{$row->{'LoanMaturity.Maturity'}});
    $status_hash{$row->{'Status'}} = 0 if (! $status_hash{$row->{'Status'}});
    $portfolios_accrued_hash{$row->{'PortfolioName'}} = 0 if (! $portfolios_accrued_hash{$row->{'PortfolioName'}});
    $loanlength_accrued_hash{$row->{'LoanMaturity.Maturity'}} = 0 if (! $loanlength_accrued_hash{$row->{'LoanMaturity.Maturity'}});
    $status_accrued_hash{$row->{'Status'}} = 0 if (! $status_accrued_hash{$row->{'Status'}});
    
    $portfolios_hash{$row->{'PortfolioName'}} = $portfolios_hash{$row->{'PortfolioName'}} + 1;
    $loanlength_hash{$row->{'LoanMaturity.Maturity'}} = $loanlength_hash{$row->{'LoanMaturity.Maturity'}} + 1;
    $status_hash{$row->{'Status'}} = $status_hash{$row->{'Status'}} + 1;
    $portfolios_accrued_hash{$row->{'PortfolioName'}} = $portfolios_accrued_hash{$row->{'PortfolioName'}} + $row->{'Accrual'};
    $loanlength_accrued_hash{$row->{'LoanMaturity.Maturity'}} = $loanlength_accrued_hash{$row->{'LoanMaturity.Maturity'}} + $row->{'Accrual'};
    $status_accrued_hash{$row->{'Status'}} = $status_accrued_hash{$row->{'Status'}} + $row->{'Accrual'};
  }
  
  $csv->eof or $csv->error_diag();
  close $fh;
  
  $self->debug("Total of " . $#rows . " notes received");
  
  $self->{'notes_invested_rows'} = \@rows;
  $self->{'notes_invested_rows_headers'} = $columns;
  $self->{'notes_invested_received_csv'} = 1;
  
  $self->{'notes_invested_porfolios'} = %portfolios_hash;
  $self->{'notes_invested_loanlength'} = %loanlength_hash;
  $self->{'notes_invested_status'} = %status_hash;
  
  if (! $self->{'debug'})
  {
    unlink( 'notes_invested.csv' );
  }
  
  return @row_id_array;
}

sub get_account_statistics
{
  my $self = shift;
  
  if (! $self->{'is_logged_in'})
  {
    $self->debug("Detected as not logged in");
    $self->login();
  }
  
  $self->debug("Getting account summary");
  
  my $mech = $self->{'mech'};
  $mech->get( "https://www.lendingclub.com/account/summary.action" );
  
  my $htmlver = $mech->content( );
  
  $self->{'interest_received'} = $1 if ($htmlver =~ m!<label\s*>\s*Interest\s+Received\s*</label>\s*<label\s*>\s*<span\s*>\s*\$(.*?)\s*</span>\s*</label>!is);
  $self->{'account_total'} = $1 if ($htmlver =~ m!<label\s*>\s*Account\s+Total\s*</label>\s*<label\s*>\s*<span\s*>\s*\$(.*?)\s*</span>\s*</label>!is);
  $self->{'in_funding'} = $1 if ($htmlver =~ m!<p\s*>\s*In\s+Funding\s+Notes\s*</p>\s*<span\s*>\s*\$(.*?)\s*</span>!is);
  $self->{'available_cash'} = $1 if ($htmlver =~ m!<p\s*>\s*Available\s+Cash\s*</p>\s*<span\s*>\s*\$(.*?)\s*</span>!is);
  $self->{'outstanding_principal'} = $1 if ($htmlver =~ m!<p>\s*Outstanding\s+Principal\s*</p>\s*<span\s*>\s*\$(.*?)\s*</span>!is);
  $self->{'accrued_interest'} = $1 if ($htmlver =~ m!<p\s*>\s*Accrued\s+Interest\s*</p>\s*<span\s*>\s*\$(.*?)\s*</span>!is);
  $self->{'total_note_count'} = $1 if ($htmlver =~ m!<a\s+href="#"\s*><strong>My Notes at-a-Glance \((\d+)\)</strong></a>!is);
  $self->{'total_paid'} = $1 if ($htmlver =~ m!<p\s*>\s*Payments\s+To\s+Date\s*</p>\s*<span>\s*\$(.*?)\s*</span>!is);
  $self->{'principal_paid'} = $1 if ($htmlver =~ m!<p\s*>\s*Principal\s*</p>\s*<span\s*>\s*\$(.*?)\s*</span>!is);
  $self->{'interest_paid'} = $1 if ($htmlver =~ m!<p\s*>\s*Interest\s*</p>\s*<span\s*>\s*\$(.*?)\s*</span>!is);
  $self->{'late_fees'} = $1 if ($htmlver =~ m!<p\s*>\s*Late\s+Fees\s*</p>\s*<span\s*>\s*\$(.*?)\s*</span>!is);
  $self->{'net_annualized_return'} = $1 if ($htmlver =~ m!<label\s*>\s*Net\s+Annualized\s+Return\s*</label>\s*<label\s*>\s*<span\s*>\s*(.*?)\s*</span>\s*</label>!is);
  
  $self->{'interest_received'} = $self->format_dollar_amount($self->{'interest_received'});
  $self->{'account_total'} = $self->format_dollar_amount($self->{'account_total'});
  $self->{'in_funding'} = $self->format_dollar_amount($self->{'in_funding'});
  $self->{'available_cash'} = $self->format_dollar_amount($self->{'available_cash'});
  $self->{'outstanding_principal'} = $self->format_dollar_amount($self->{'outstanding_principal'});
  $self->{'accrued_interest'} = $self->format_dollar_amount($self->{'accrued_interest'});
  $self->{'total_paid'} = $self->format_dollar_amount($self->{'total_paid'});
  $self->{'principal_paid'} = $self->format_dollar_amount($self->{'principal_paid'});
  $self->{'interest_paid'} = $self->format_dollar_amount($self->{'interest_paid'});
  $self->{'late_fees'} = $self->format_dollar_amount($self->{'late_fees'});
  $self->{'net_annualized_return'} = $self->format_percentage($self->{'net_annualized_return'});
  
  $self->debug("Interest received: " . $self->{'interest_received'});
  $self->debug("Account total: " . $self->{'account_total'});
  $self->debug("In funding: " . $self->{'in_funding'});
  $self->debug("Available cash: " . $self->{'available_cash'});
  $self->debug("Outstanding principal: " . $self->{'outstanding_principal'});
  $self->debug("Accrued interest: " . $self->{'accrued_interest'});
  $self->debug("Total number of notes: " . $self->{'total_note_count'});
  $self->debug("Total paid: " . $self->{'total_paid'});
  $self->debug("Principal paid: " . $self->{'principal_paid'});
  $self->debug("Interest paid: " . $self->{'interest_paid'});
  $self->debug("Late fees: " . $self->{'late_fees'});
  $self->debug("Net annualized return: " . $self->{'net_annualized_return'});
  
  $mech->get( "https://www.lendingclub.com/account/NotesSummaryAj.action?rnd=" . time );
  
  my $jsontxt = $mech->content( );
  my $json = JSON->new->allow_nonref;
  my $jsonstruct = $json->decode( $jsontxt );
  
  my $toreturn = {};
  $toreturn->{'interest_received'} = $self->{'interest_received'};
  $toreturn->{'account_total'} = $self->{'account_total'};
  $toreturn->{'available_cash'} = $self->{'available_cash'};
  $toreturn->{'in_funding'} = $self->{'in_funding'};
  $toreturn->{'outstanding_principal'} = $self->{'outstanding_principal'};
  $toreturn->{'accrued_interest'} = $self->{'accrued_interest'} . "\n";
  $toreturn->{'total_note_count'} = $self->{'total_note_count'};
  $toreturn->{'total_paid'} = $self->{'total_paid'};
  $toreturn->{'principal_paid'} = $self->{'principal_paid'};
  $toreturn->{'interest_paid'} = $self->{'interest_paid'};
  $toreturn->{'late_fees'} = $self->{'late_fees'};
  $toreturn->{'net_annualized_return'} = $self->{'net_annualized_return'};
  
  $toreturn->{'notecount_fullypaid'} = $self->format_numeric($jsonstruct->{'fullyPaid'});
  $toreturn->{'notecount_late16to30'} = $self->format_numeric($jsonstruct->{'late16to30'});
  $toreturn->{'notecount_infunding'} = $self->format_numeric($jsonstruct->{'inFunding'});
  $toreturn->{'notecount_late31to120'} = $self->format_numeric($jsonstruct->{'late31to120'});
  $toreturn->{'notecount_current'} = $self->format_numeric($jsonstruct->{'issuedAndCurrent'});
  $toreturn->{'notecount_default'} = $self->format_numeric($jsonstruct->{'defaultL'});
  $toreturn->{'notecount_chargedoff'} = $self->format_numeric($jsonstruct->{'chargedOff'});
  
  $toreturn->{'noteamt_fullypaid'} = $self->format_dollar_amount($jsonstruct->{'fullyPaidAmount'});
  $toreturn->{'noteamt_late16to30'} = $self->format_dollar_amount($jsonstruct->{'late16to30Amount'});
  $toreturn->{'noteamt_infunding'} = $self->format_dollar_amount($jsonstruct->{'inFundingAmount'});
  $toreturn->{'noteamt_late31to120'} = $self->format_dollar_amount($jsonstruct->{'late31to120Amount'});
  $toreturn->{'noteamt_current'} = $self->format_dollar_amount($jsonstruct->{'issuedAndCurrentAmount'});
  $toreturn->{'noteamt_default'} = $self->format_dollar_amount($jsonstruct->{'defaultLAmount'});
  $toreturn->{'noteamt_chargedoff'} = $self->format_dollar_amount($jsonstruct->{'chargedOffAmount'});
  return $toreturn;
}

sub format_dollar_amount
{
  my $self = shift;
  my $amt = shift;
  
  if ($amt)
  {
    #$amt =~ s/[\$\,]//g;
    $amt = $self->format_numeric($amt);
  }
  elsif (! ($amt eq '0' || $amt eq '0.00'))
  {
    $amt = 'N/A';
  }
  return $amt;
}

sub format_percentage
{
  my $self = shift;
  my $amt = shift;
  
  if ($amt)
  {
    $amt =~ s/[\%\,\s]//g;
  }
  elsif (! ($amt eq '0' || $amt eq '0.00'))
  {
    $amt = 'N/A';
  }
  return $amt;
}

sub format_numeric
{
  my $self = shift;
  my $amt = shift;
  
  if ($amt)
  {
    $amt =~ s/[^0-9\.]//g;
    if ($amt eq '')
    {
      $amt = 'N/A';
    }
  }
  elsif (! ($amt eq '0' || $amt eq '0.00'))
  {
    $amt = 'N/A';
  }
  return $amt;
}

sub check_verified
{
  my $self = shift;
  my $value = shift;
  
  return ($value =~ m!\*$!);
}

sub login
{
  my $self = shift;
  
  $self->debug("Logging in.");
  
  my $mech = $self->{'mech'};
  
  $mech->get( "https://www.lendingclub.com/account/summary.action" );
  
  $mech->submit_form(
    with_fields    => { login_email  => $self->{'username'}, login_password => $self->{'password'} }
  );
  
  my $htmlver = $mech->content( );
  
  if ($htmlver =~ m!<li\s+class="first"\s*>\s*<a\s+href="/account/profile.action">\s*Welcome!is)
  {
    $self->{'is_logged_in'} = 1;
    $self->debug("Successfully logged in.");
  }
  else
  {
    die("Login and password incorrect");
  }
}

1;
__END__

=head1 NAME

LendingClub - Perl extension for interacting with Lending Club

=head1 SYNOPSIS

  use LendingClub;
  
  my $lc = LendingClub->new( { username => 'email@domain.com', password => 'p4ssw0rd', debug => 1, noproxy => 1 } );
  my %stats = $lc->get_account_statistics(); #return information about my account to a hash
  my @invested_notes = $lc->get_invested_notes();
  my @available_notes = $lc->get_available_notes();
  my $note = $lc->get_note_data(12345); #return basic information about this note as a hash
  
  #get some information about the area that this member is from
  my $citystate = $note->{'member'}->{'location'}->{'value'}; #pull out the "location" (city, state) of the member
  my $location_info = $lc->get_location_info($citystate);
  my $avg_housing = $location_info->{'housing'}[0]->{'value'}[0]->{'median_dollars'}[0]->{'content'};
  my $avg_income = $location_info->{'economy'}[0]->{'income'}[0]->{'median_household_income_dollars'}[0]->{'content'};

=head1 DESCRIPTION

This perl module is intended to act as a loose API for interacting with the website lendingclub.com.

Prerequisite Perl Modules:

  WWW::Mechanize
  Text::CSV
  XML::Simple
  HTTP::Request
  JSON

=head1 METHODS

The following methods are provided:

(NOTE: In general, if any method/value produces a "null" or invalid value, this module will attempt to normalize that to "N/A")

=over 4

=item B<my $lc = LendingClub-E<gt>new( { username =E<gt> 'your@email.com', password =E<gt> 'passwd' } );>

The constructor takes hash style parameters.  The following
parameters are recognized:

  username:        email / username for your Lending Club account
  password:        the password to the username logging in
  debug:           enable debugging withe the module (bool)
  noproxy:         disable the underlying proxy in WWW::Mechanize (bool)
  
=item B<my @notes_by_id = $lc-E<gt>get_invested_notes();>

The C<get_invested_notes()> function serves two purposes:
  1. Return an array of notes that have been invested in by the logged in user in an array, where each element in the array is a note ID
  2. Load up personal investment statistics about the note into memory, which will be available in later calls in C<get_note_data(...)> calls.  Without making this call first, some data may be unavailable to C<get_note_data()> execution
  
  Example:
  
  foreach my $noteid ($lc->get_invested_notes())
  {
    my $note_data = $lc->get_note_data($noteid);
  }
  
  
=item B<my @notes_by_id = $lc-E<gt>get_avaialable_notes()>;

The C<get_avaialable_notes()> function serves two purposes:
  1. Return an array of notes that have are available for investing by the logged in user in an array, where each element in the array is a note ID
  2. Load up additional note data into memory, which will be available in later calls in C<get_note_data(...)> calls.  Without making this call first, some data may be unavailable to C<get_note_data()> execution
  
  Example:
  
  foreach my $noteid ($lc->get_avaialable_notes())
  {
    my $note_data = $lc->get_note_data($noteid);
  }
  

=item B<my $stats = $lc-E<gt>get_account_statistics();>

The C<get_account_statistics()> function will bring back statistics of your account.
The following variables are available in the hash:

  interest_received     (expected: numeric decimal representing the dollar amount of interest received)
  account_total         (expected: numeric decimal representing the total amount of dollars in the account)
  in_funding            (expected: numeric decimal representing the dollar amount currently in funding)
  available_cash        (expected: numeric decimal representing the dollar amount available for investment or withdrawl)
  outstanding_principal (expected: numeric decimal representing the outstanding dollar amount of principal investment)
  accrued_interest      (expected: numeric decimal representing the dollar amount of interest accrued, assuming all payments remain current)
  total_note_count      (expected: numeric integer describing the total number of notes that have been invested in)
  total_paid            (expected: numeric decimal representing the invested dollar amount paid back in total)
  principal_paid        (expected: numeric decimal representing the invested dollar amount paid back from principal)
  interest_paid         (expected: numeric decimal representing the invested dollar amount paid back from interest)
  late_fees             (expected: numeric decimal representing the invested dollar amount paid in late fees)
  net_annualized_return (expected: numeric decimal representing the net percentage annualized return)
  
To get this data, for example, $stats->{'total_paid'}

=item B<my $note = $lc-E<gt>get_note_data(12345);>

The C<get_note_data()> function takes in a note ID and returns information about the note in a hash.
Information about the note, information about the posts, as well as information about the member is available.

In this sample call...

C<$note-E<gt>{'member'}> may contain the a hash of the following:

  total_credit_lines                (expected: numeric integer representing the total number of credit lines under the borrower's name)
  open_credit_lines                 (expected: numeric integer representing total count of open credit lines)
  recent_inquiries                  (expected: numeric integer representing total count of recent inquiries)
  earliest_credit_line              (expected: string {MM/YYYY})
  debt_to_income_pct                (expected: numeric decimal representing the debt to income percentage for the borrower)
  revolving_credit_balance          (expected: numeric decimal representing $ of revolving utilization of credit)
  revolving_credit_utilization_pct  (expected: numeric decimal representing revolving % of credit utilized each month)
  
  delinquent_accounts               (expected: numeric integer representing the total number of delinquent accounts under the borrower's name)
  recent_delinquencies              (expected: numeric integer representing the total number of recent delinquencies under the borrower's name)
  last_delinquency_months_elapsed   (expected: numeric integer representing the number of months elapsed since the last delinquency under the borrower's name)
  delinquent_amount                 (expected: numeric decimal represing total $ amount delinquent)
  
  gross_income                      (expected: numeric decimal representing $ per month earned)
  current_employer                  (expected: string {unformatted})
  length_of_employment              (expected: numeric integer representing months of employment.  'N/A' for <1 year)
  
  home_ownership                    (expected: string {OWN, RENT or MORTGAGE})
  location                          (expected: string {City, ST})
  
  public_records_count              (expected: numeric integer representing total count of public records on file)
  last_public_record_months_elapsed (expected: numeric integer representing the number of months since the last public record)
  
  name                              (expected: string representing the member's name)

  NOTE:
  - Each of these will have two sub-values: "value" and "verified".  "Value" will have the aforementioned value and "verified" will have a "1" if the value has been verified by LendingClub.
  - For example, to get the income, use
  
    $note->{'member'}->{'gross_income'}->{'value'}>
  
  and to check the verification of that
    
    $note->{'member'}->{'gross_income'}->{'verified'}
  
C<$note-E<gt>{'loan'}> may contain the a hash of the following:
  num_investors            (expected: a numeric integer representing the total number of investers who have invested in the loan)
  
  amount_requested         (expected: a numeric decimal representing the dollar amount requested by the borrower)
  funding_received         (expected: string representing the "funding received" for the loan.  See also: funding_received_amt and funding_received_pct)
  funding_received_pct     (expected: a numeric decimal representing the percentage of requested funding received)
  funding_received_amt     (expected: a numeric decimal representing the dollar amount of requested funding received)
  
  interest_rate            (expected: a numeric decimal representing the percentage interest rate)
  monthly_payment          (expected: a numeric decimal representing the dollar amount scheduled for payment each month for this loan)
  loan_grade               (expected: string {{XY} where X is the A-G grade and Y is the 1-5 subgrade})
  loan_length              (expected: a numeric integer representing the number of months the loan was scheduled for)
  
  loan_status              (expected: string {In Funding, Issued, Current, Paid Off, Defaulted, < 30 Days Late, > 30 Days Late})
  loan_submitted_date_time (expected: string {Mm/Dd/YY Hh:NN [AM/PM]})
  listing_expires_in       (expected: a numeric integer representing the APPROXIMATE number of minutes until the loan expires.  may also be empty or "EXPIRED")
  
  loan_purpose             (expected: string {'Debt consolidation', 'Wedding Expenses', etc})
  
  title                    (expected: string representing the title of the loan)
  description              (expected: string representing the description of the loan, as described by the borrower)

If the get_invested_notes() function was previously called, the following data may also be available in the $note->{'loan'} hash:

  is_invested              (expected: boolean representing if this note has been invested in by the current uesr)
  amount_lent              (expected: numeric integer representing the sum of dollars lent into this note
  remaining_principal      (expected: numeric decimal representing the total principal remaining to be paid back to the current user)
  payments_received        (expected: numeric decimal representing the total amount of money that has been received from payments in this note)
  next_payment_date        (expected: string {MM/DD/YYYY} of the next payment due date)
  in_portfolio_names       (expected: string (csv) of portfolio names that this note is invested in)
  in_portfolio_ids         (expected: string (csv) of portfolio IDs that this note is invested in)
  
If the get_available_notes() function was previously called, the following data may also be available in the $note->{'member'} hash:

  job_title                (expected: string representing the self-described job title by the member)
  employment_status        (expected: string {'EMPLOYED', 'SELFEMPLOYED', 'RETIRED', 'CONTRACTOR', 'STUDENT', 'UNEMPLOYED', 'PART_TIME'})
  gross_income
     ->verification_status (expected: string {'VERIFIED', 'REQUESTED', 'FAILED_1', 'NOT_REQUIRED'})
  
=item B<$location_info = $lc-E<gt>get_location_info('Massillon, OH');>

=item B<$location_info = $lc-E<gt>get_location_info('Massillon','OH');>

Uses the API at http://www.fizber.com to get information about a city.  This may be useful for gathering general statistics about an area, including housing and economy information.  A great variety of information is available as a result of this call, and for an example full XML, please see:
http://www.fizber.com/xml_data/xml_neighborhood_info.xml?type=city&amp;state=OH&amp;city=Massillon

For example, to get the median househod income in dollars:

  $location_info->{'economy'}[0]->{'income'}[0]->{'median_household_income_dollars'}[0]->{'content'};

=item B<$numericval = $lc-E<gt>format_numeric("$123,456.00");>

This is used internally, but may be used externally, to remove any non-numerics.  Useful for stripping out percentage (%), dollar ($), and comma (,) symbols, as well as trimming spaces, etc.

=back

=head1 SEE ALSO

www.lendingclub.com

www.fizber.com

=head1 AUTHOR

Shane P Connelly <shane@eskibars.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Shane P Connelly

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
