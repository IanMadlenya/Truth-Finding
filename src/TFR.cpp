#include <Rcpp.h>
using namespace Rcpp;
#define PBSTR "||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||"
#define PBWIDTH 60

// [[Rcpp::export]]
void printProgress (double percentage)
{
    int val = (int) (percentage * 100);
    int lpad = (int) (percentage * PBWIDTH);
    int rpad = PBWIDTH - lpad;
    printf ("\r%3d%% [%.*s%*s]", val, lpad, PBSTR, rpad, "");
    fflush (stdout);
}

// [[Rcpp::export]]
int one_cat_zero_begin(NumericVector probs){
  int k = probs.size();
  int res = 0;
  double z=sum(probs);
  if(z!=1){
    for(int i=0;i<k;++i){
      probs[i]=probs[i]/z;
    }
  }
  IntegerVector ans(k);
  rmultinom(1, probs.begin(), k, ans.begin());
  for(int j=0;j<k;++j){
    if(ans[j]==1){
      res=j;
      break;
    }
  }
  return res;
}

// [[Rcpp::export]]
List truthfinding_binary(IntegerVector facts,IntegerVector fcidx, IntegerMatrix claims, IntegerMatrix ctsc, NumericMatrix beta, NumericMatrix alpha0, NumericMatrix alpha1){
  int nfacts=facts.size();
  int nsources=alpha0.row();
  int expand_source_claim=nsources*2;
  int idx=0;
  int startidx=0,endidx=0;	// claim start and end index for each fact
  int sid=0,o=0,t=0;		// tmp variable in locating claims in ctsc
  int fact_pre=0,fact_aft=0;
  NumericVector probs(2);
  double conditional_claim0=1, conditional_claim1=1;
  
  // main gibbs loop
  // 1. for each fact f...
  for(int f = 0; f < nfacts; ++f){
    startidx=fcidx[f];
    endidx=fcidx[f+1];
    fact_pre=facts[f];
    
    // 2. for each claim c in fact f...
    for(int c = startidx; c < endidx; ++c){
      sid=claims(c,1);
      o=claims(c,2);

      // 2.0 generate sample probability for t=0
      t=0;			// when f is true
      conditional_claim0=1;	//reset conditional claim probability
      idx=sid*2;
      conditional_claim0 = conditional_claim0*
	((double)ctsc(idx+o,3)+alpha0(sid,o))/ //equation (2)
	((double)ctsc(idx,3)+(double)ctsc(idx+1,3)+alpha0(sid,0)+alpha0(sid,1));

      // 2.1 generate sample probability for t=1
      t=1;			// when f is false
      conditional_claim1=1;	// reset conditional claim probability
      idx= expand_source_claim + idx
      conditional_claim1=conditional_claim1*
	((double)ctsc(idx+o,3)+alpha1(sid,o))/ //equation (2)
	((double)ctsc(idx,3)+(double)ctsc(idx+1,3)+alpha1(sid,0)+alpha1(sid,1));
    }

    probs[0] = beta(f,0)*conditional_claim0;
    probs[1] = beta(f,1)*conditional_claim1;
    
    // sample and update facts
    fact_aft=one_cat_zero_begin(probs);
    
    // update ctsc
    for(int c = startidx; c < endidx; ++c){
      sid=claims(c,1);
      o=claims(c,2);

      // pre - 1
      idx=fact_pre*expand_source_claim+sid*2+o;
      ctsc(idx,3)=ctsc(idx,3)-1;

      // aft + 1
      idx=fact_aft*expand_source_claim+sid*2+o;
      ctsc(idx,3)=ctsc(idx,3)+1;
    }
    
  }
}

