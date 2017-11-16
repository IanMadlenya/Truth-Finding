## data.fram version of %in%
## returns a logical vector indicating if there is a match or not for EACH ROW of its left operand.
`%IN%` <- function(df1,df2){
    if( !is(df1,"data.frame") | !is(df2,"data.frame")){
        stop("inputs must be data.frames")
    }
    if(!identical(vapply(df1,class,FUN.VALUE = "a",USE.NAMES = FALSE),vapply(df2,class,FUN.VALUE = "a",USE.NAMES = FALSE))){
        stop("columns of inputs not aligned")
    }
    if(ncol(df1)==1){
        return(df1[[1]]%in%df2[[1]])
    }
    res <- vapply(1:ncol(df1),function(i){
        match(df1[[i]],df2[[i]], nomatch = 0L)
    },FUN.VALUE = rep(0L,nrow(df1)),USE.NAMES = FALSE)

    return(apply(res,MARGIN = 1,function(x){
        if(x[1]!=0L){
            all(x[-1]==x[1])
        }else{
            FALSE
        }
    }))
}

## label:
## e: entity
## a: attribute
## s: source
## o: claim
## t: truth

## raw data
rawdb <- unique(data.frame(e=sample(letters[1:4],30,replace = TRUE),a=sample(c("spa","breakfast","iron"),size = 30,replace = TRUE),s=sample(toupper(letters[1:3]),30,replace = TRUE),stringsAsFactors = FALSE))

    function input:
    beta: Fx2 numeric matrix, each row is the beta prior the corresponding fact
    alpha0: Sx2 numeric matrix, each row is the beta prior for the corresponding source FPR, each element is at least 1
alpha1: Sx2 numeric matrix, each row is the beta prior for the corresponding source sensitivity, each element is at least 1

checkprior <- function(prior,class=character(),nrow=NULL,ncol=NULL,length=NULL,elementclasses=NULL){
    is(prior,class) &
    ifelse(!is.null(nrow),nrow(prior)==nrow,TRUE) &
    ifelse(!is.null(ncol),ncol(prior)==ncol,TRUE) &
    ifelse(!is.null(length),length(prior)==length,TRUE) &
    ifelse(!is.null(elementclasses),all(sapply(prior,class)==elementclasses),TRUE)
}

TF_binary <- function(rawdb,beta,alpha0,alpha1,burnin,maxit,sample_step){
    burnin <- as.integer(burnin)
    maxit <- as.integer(maxit)
    sample_step<- as.integer(sample_step)
    ## integrity check part1
    if(is.matrix(rawdb)) rawdb <- as.data.frame(rawdb)
    if(!checkprior(rawdb,"data.frame",ncol=3) | any(duplicated(rawdb))) stop("rawdb must be a data.frame or matrix with exactly 3 columns and no duplicate entries")

    ## 1. mappers
    factsmapper <- unique(rawdb[,c("e","a")])
    factsmapper$fid <- 0L:(nrow(factsmapper)-1L)
    sourcesmapper <- unique(rawdb[,c("s")])
    sourcesmapper <- data.frame(s=sourcesmapper,sid=0L:(length(sourcesmapper)-1L),stringsAsFactors = FALSE)
    
    ## integrity check part2
    if(is.numeric(beta)) beta <- matrix(beta,nrow=nrow(factsmapper),ncol = 2)
    if(is.numeric(alpha0)) alpha0 <- matrix(alpha0,nrow=nrow(sourcesmapper),ncol = 2)
    if(is.numeric(alpha1)) alpha1 <- matrix(alpha1,nrow=nrow(sourcesmapper),ncol = 2)
    if(!checkprior(beta,"matrix",nrow(factsmapper),2)) stop("beta should be of length 1 or a numeric matrix of dimension n.facts x 2")
    if(!checkprior(alpha0,"matrix",nrow(sourcesmapper),2) |
       !checkprior(alpha1,"matrix",nrow(sourcesmapper),2)) stop("alpha0 or alpha1 should both be of length 1 or a numeric matrix of dimension n.sources x 2")
    
    ## 2. claims
    claims <- do.call(rbind.data.frame,lapply(split(rawdb,rawdb$e),function(d){
        tmp <- expand.grid(unique(d$a),unique(d$s),stringsAsFactors = FALSE)
        names(tmp) <- c("a","s")
        tmp$o <- as.integer(tmp %IN% d[,c("a","s")])
        tmp$e <- d$e[1]
        tmp
    }))
    row.names(claims) <- NULL
    claims <- merge(merge(claims,factsmapper,all.x = TRUE,sort = FALSE)[c("fid","s","o")],sourcesmapper,all.x = TRUE,sort = FALSE)[c("fid","sid","o")]
    claims <- claims[order(claims$fid,claims$sid,claims$o),]
    
    ## 3. initialize truth
    facts <- data.frame(fid=factsmapper$fid,t=sample(c(0L,1L),nrow(factsmapper),replace = TRUE),stringsAsFactors = FALSE)
    facts <- facts[order(facts$fid),]
    
    ## count, truth-source-claim
    ## raw sensitivity and FPR data
    ctsc <- expand.grid(c(0L,1L),sourcesmapper$sid,c(0L,1L),stringsAsFactors = FALSE)
    names(ctsc) <- c("t","sid","o")
    cwit <- merge(claims,facts,all.x = TRUE,sort = FALSE) # claim with initial truth, a tmp variable in calculating ctsc
    ctsc <- merge(ctsc,aggregate(fid~sid+t+o,data = cwit,FUN = length),all.x = TRUE,sort = FALSE)
    rm(cwit)
    names(ctsc)[4] <- "count"
    ctsc$count[is.na(ctsc$count)] <- 0L
    ctsc <- ctsc[order(ctsc$t,ctsc$sid,ctsc$o),]
    
    ## fact-claim index, claim start posiitons of each fact
    ## to simplify C++ code, here the index starts with zero
    fcidx <- match(facts$fid,claims$fid)-1L             #facts and claims must be sorted beforehand
    fcidx <- c(fcidx,nrow(claims))                      #append end position for easier representation

    truthfinding_binary(facts=facts$t,fcidx=fcidx, claims=as.matrix(claims), ctsc=as.matrix(ctsc), beta=beta, alpha0=alpha0, alpha1=alpha1,burnin = burnin, maxit = maxit,sample_step = sample_step)
    
}
