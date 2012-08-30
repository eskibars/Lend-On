package LendingClub::Note;

use 5.010000;
use strict;
use warnings;
use WWW::Mechanize;

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
  
  return $self;
}

sub parse_loandetail
{
  my $self = shift;
  my $html = shift;
  $self->{'amount_requested'} = $1 if ($html =~ m!<th\s*>\s*Amount\s+Requested\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $self->{'loan_purpose'} = $1 if ($html =~ m!<th\s*>\s*Loan\s+Purpose\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $self->{'loan_grade'} = $1 if ($html =~ m!<th\s*>\s*Loan\s+Grade\s*</th>\s*<td[^\.]*?>\s*<span[^\.]*?>\s*(.*?)\s*</span>\s*</td>!is);
  $self->{'interest_rate'} = $1 if ($html =~ m!<th\s*>\s*Interest\s+Rate\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $self->{'monthly_payment'} = $1 if ($html =~ m!<th\s*>\s*Monthly\s+Payment\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $self->{'loan_length'} = $1 if ($html =~ m!<th\s*>\s*Loan\s+Length\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $self->{'funding_received'} = $1 if ($html =~ m!<th\s*>\s*Funding\s+Received\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $self->{'num_investors'} = $1 if ($html =~ m!<th\s*>\s*Investors\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $self->{'loan_status'} = $1 if ($html =~ m!<th\s*>\s*Loan\s+Status\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $self->{'loan_submitted_date_time'} = $1 if ($html =~ m!<th\s*>\s*Loan\s+Submitted\s+on\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $self->{'title'} = $1 if ($html =~ m!<h1>\s*(.*?)</h1>!is);
  $self->{'credit_review_status'} = $1 if ($html =~ m!<th\s*>\s*Credit\s+Review\s+Status\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $self->{'listing_expires_in'} = $1 if ($html =~ m!<th\s*>\s*Listing\s+Expires\s+In\s*</th>\s*<td\s*>\s*(.*?)\s*</td>!is);
  $self->{'description'} = $1 if ($html =~ m!<div\s+class="scrub"\s+id="loan_description">\s*(.*?)\s*</div>!is);
  
  if ($self->{'credit_review_status'})
  {
    $self->{'credit_review_status'} =~ s/<[^>]*?>//g;
    $self->{'credit_review_status'} =~ s/\&nbsp;//g;
    $self->{'credit_review_status'} =~ s/^\s*//g;
    $self->{'credit_review_status'} =~ s/\s*$//g;
  }
  
  if ($self->{'listing_expires_in'})
  {
    $self->{'listing_expires_in'} =~ s/\(.*?\)//;
    my $hr = $1 if ($self->{'listing_expires_in'} =~ m!(\d+)h!i);
    my $mn = $1 if ($self->{'listing_expires_in'} =~ m!(\d+)m!i);
    my $da = $1 if ($self->{'listing_expires_in'} =~ m!(\d+)d!i);
    if ($hr || $mn || $da)
    {
      $mn = 0 if (! $mn);
      $da = 0 if (! $da);
      $hr = 0 if (! $hr);
      $self->{'listing_expires_in'} = $mn + $hr * 60 + $da * 1440;
    }
    
  if ($self->{'funding_received'} =~ m!([\$\d\,\.]*)\s+\(([\%\d\,\.]*)\s+funded\)!)
  {
    $self->{'funding_received_amt'} = $self->{'lendingclub'}->format_dollar_amount($1);
    $self->{'funding_received_pct'} = $self->{'lendingclub'}->format_percentage($2);
  }
  }
  
  $self->{'description'} =~ s/<.*?>//g;
  
  $self->{'amount_requested'} = $self->{'lendingclub'}->format_dollar_amount($note->{'loan'}->{'amount_requested'});
  $self->{'interest_rate'} = $self->{'lendingclub'}->format_percentage($note->{'loan'}->{'interest_rate'});
  $self->{'monthly_payment'} = $self->{'lendingclub'}->format_dollar_amount($note->{'loan'}->{'monthly_payment'});
  $self->{'num_investors'} = $self->{'lendingclub'}->format_numeric($note->{'loan'}->{'num_investors'});
  if ($self->{'loan_length'} =~ m!(\d+)\s+year[s]*!i)
  {
    $self->{'loan_length'} = (int($1) * 12);
  }
  elsif ($self->{'loan_length'} =~ m!(\d+)\s+month[s]*!i)
  {
    $self->{'loan_length'} = int($1);
  }
  else
  {
    $self->{'loan_length'} = 'N/A';
  }
}

sub invest
{
  my $self = shift;
  my $amount = shift;
  my $portfolioname = shift;
  
  my $loanid = $self->{'id'};
  
  my $url = 'https://www.lendingclub.com/browse/addToPortfolio.action?loan_id=' . $loanid . '&loan_amount=' . $amount;
  
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
          my $post = 'lcportfolio_description=&record_id=1&lcportfolio_name=' . $portfolionameencoded . '&loan_id=' . $loanid . '&order_id=' . $orderid;
          $post .= ($portfolioexists ? '&method=addToLCPortfolio' : '&method=createLCPortfolio');
          $request->content($post);
          $mech->request($request);
        }
      }
    }
  }
}