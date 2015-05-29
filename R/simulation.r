FormAttributes <- function(DAG, parents, dataform, LTCF, tvals) {
	list(	DAG=DAG,
			parents=parents,
			dataform = dataform,
			LTCF = LTCF,
			tvals = tvals,
			node_nms = sapply(N(DAG), '[[', "name"),	# node names from the DAG name attributes
			actnodes = attr(DAG, "actnodes"),	# save the action nodes (if defined)
			acttimes = attr(DAG, "acttimes"),	# action time points (if defined)
			attnames = attr(DAG, "attnames"),	# save the attribute names (if defined)
			attrs = attr(DAG, "attrs")			# save the attribute values (if defined)
			)
}
# copy all DAG related attributes from a full data.frame attribute list (skipping row names and such)
# can modify some of the attributes, s.a., dataform, tvals & LTCF if provided
CopyAttributes <- function(attrslist, dataform=NULL, tvals=NULL, LTCF=NULL) {
	list(	DAG=attrslist[["DAG"]],
			parents=attrslist[["parents"]],
			dataform = if (!is.null(dataform)) dataform else attrslist[["dataform"]],
			LTCF = if (!is.null(LTCF)) LTCF else attrslist[["LTCF"]],
			tvals = if (!is.null(tvals)) tvals else attrslist[["tvals"]],
			node_nms = attrslist[["node_nms"]],
			actnodes = attrslist[["actnodes"]],
			acttimes = attrslist[["acttimes"]],
			attnames = attrslist[["attnames"]],
			attrs = attrslist[["attrs"]],
			target = attrslist[["target"]]
			)
}

get_allts <- function(obs.df) { # calculate actual time values used in the simulated data (wide format)
	node_nms <- attributes(obs.df)$names[-1]
    all_ts <- as.integer(unique(sapply(strsplit(node_nms, "_"), '[', 2)))
    all_ts <- sort(all_ts[!is.na(all_ts)]) #remove NA/NULL cases and sort
}
get_gennames <- function(obs.df) { # grab generic names (without time points) from simulated data (wide format)
	node_nms <- attributes(obs.df)$names[-1]
    gennames <- as.character(unique(sapply(strsplit(node_nms, "_"), '[', 1)))
    # gennames <- sort(gennames[!is.na(gennames)]) #remove NA/NULL cases and sort
}

# given names of actions, extract the corresponding DAG.action objects from DAG
getactions <- function(DAG, actions) {
	if (!is.character(actions)) stop("actions must be a character vector of action names")

	# check the actions actually exist in the DAG, then grab them
	all_action_DAGs <- A(DAG)
	if (length(all_action_DAGs)<1) stop("DAG objects contains no actions, define actions with DAG+action before simulating action-specific data...")
	all_action_names <- sapply(all_action_DAGs, function(DAG) attr(DAG, "actname"))
	# verify that each action name in actions has only 1 unique match
	action_idx_sel <- NULL
	for (action in actions) {
		action_idx <- which(all_action_names %in% action)
		if (length(action_idx)<1) {
			stop("Couldn't locate action: "%+% action %+% " , first define action by adding it to the DAG object with DAG+action")
		} else if (length(action_idx)>1) {
			stop("Found more than one action matching action name: " %+% action)
		}
		action_idx_sel <- c(action_idx_sel, action_idx)
	}
	actions <- all_action_DAGs[action_idx_sel]							
}

# Internal function for simulation data from any DAG
# If prev.data is not NULL all the nodes in DAG will be evaluated in the environment of prev.data alone
simFromDAG <- function(DAG, Nsamp, wide = TRUE, LTCF = NULL, rndseed = NULL, prev.data = NULL) {
# simFromDAG <- function(DAG, Nsamp, data_fmt = "wide", LTCF = NULL, rndseed = NULL, prev.data = NULL) {
	if (!is.null(rndseed)) {
		set.seed(rndseed)
	}
	if (!is.DAG(DAG)) stop("DAG argument must be an object of class DAG")

	categorical_for = function(probs) { # takes a matrix of probability vectors, each in its own row
		probs_cum <- matrix(nrow=nrow(probs), ncol=ncol(probs))
		probs_cum[,1] <- probs[,1]
		for (i in seq(ncol(probs))[-1]) {
			probs_cum[,i] <- rowSums(probs[,c(1:i)])
		}
		answer <- rowSums(probs_cum - runif(nrow(probs_cum)) < 0) + 1
		return(answer)
	}
	sampleNodeDistr <- function(newNodeParams, distr, EFUP.prev, cur.node, expr_str) {
		N_notNA_samp <- sum(!EFUP.prev)
		# 'below is deprecated - remove:
		if (distr=="const") {
			len_const <- length(newNodeParams$const_val)

			if (len_const!=1 & len_const!=Nsamp) stop("Incorrect length for constant values")
			if (len_const==1) {
				newVar <- rep.int(newNodeParams$const_val, Nsamp)
			} else {
				newVar <- newNodeParams$const_val
			}
		# 'below is deprecated - remove:
		} else if (distr=="unif"){
			a_low <- newNodeParams$a
			b_hi <- newNodeParams$b
			len_a <- length(a_low)
			len_b <- length(b_hi)
			# print(a_low); print(b_hi)
			if (len_a!=1 & len_a!=Nsamp) stop("Incorrect lengths of the uniform [unifmin,unifmax] intervals")
			if (len_b!=1 & len_b!=Nsamp) stop("Incorrect lengths of the uniform [unifmin,unifmax] intervals")
			if (len_a==1) a_low <- rep.int(a_low, Nsamp)
			if (len_b==1) b_hi <- rep.int(b_hi, Nsamp)
			newVar <- rep.int(NA_real_, Nsamp)
			# N_notNA_samp <- sum(!is.na(a_low))
			newVar[!EFUP.prev] <- runif(n=N_notNA_samp, min=a_low[!EFUP.prev], max=b_hi[!EFUP.prev])
		# 'below is deprecated - remove:			
		} else if (distr=="Bern") {
			# old version (creates "NA generated" warning) # newVar <- rbinom(n=Nsamp, size=1, prob=newNodeParams$Binom_prob)
			Bprobs <- newNodeParams$Binom_prob
			len_Bprobs <- length(Bprobs)
			if (len_Bprobs!=1 & len_Bprobs!=Nsamp) stop("Incorrect length for the Bernoulli probabilities")
			if (len_Bprobs==1) Bprobs <- rep.int(Bprobs, Nsamp)
			newVar <- rep.int(NA_integer_, Nsamp)
			# N_notNA_samp <- sum(!is.na(Bprobs))
			newVar[!EFUP.prev] <- rbinom(n=N_notNA_samp, size=1, prob=Bprobs[!EFUP.prev])
		# 'below is deprecated - remove:			
		} else if (distr=="cat"){
			# THIS STAGE CAN BE DONE DURING PRE-DISTRIBUTION STAGE
			# define last category probability as 1-sum(probs)
			probs <- newNodeParams$Cat_prob
			# dprint("cat probs"); dprint(probs)
			if (class(probs)%in%"list") {
				# convert each probability to a numeric vector of length Nsamp
				probs <- lapply(probs, function(prob) {
										prob <- as.numeric(prob)
										if (length(prob)==1) prob <- rep.int(prob, Nsamp)
										(prob)
									})
				probs_mtx <- do.call("cbind", probs)
			} else {
				stop("...fatal error during evaluation of the categorical probabilities...")
			}
			# lprobs <- length(probs)+1
			pnames <- "p"%+%seq(ncol(probs_mtx));
			lprobs <- ncol(probs_mtx)+1
			probs_mtx <- cbind(probs_mtx, 1-rowSums(probs_mtx))
			colnames(probs_mtx) <- c(pnames,"plast")
			# dprint("probs_mtx"); dprint(head(probs_mtx))
			pover1_idx <- which(probs_mtx[,lprobs] < 0)
			if (length(pover1_idx)>0) {
				warning("some categorical probabilities add up to more than 1, normalizing those to add up to 1")
				probs_mtx[pover1_idx, lprobs] <- 0
				probs_mtx[pover1_idx, ] <- probs_mtx[pover1_idx, ] / rowSums(probs_mtx[pover1_idx, ]) # normalize
			}
			# probs_sums <- rowSums(probs_mtx)
			# dprint("test for cat summing to 1"); dprint(all(round(probs_sums[!is.na(probs_sums)],5)==1))
			# dprint("probs_mtx"); dprint(head(probs_mtx))
			newVar <- categorical_for(probs_mtx)
			newVar <- as.factor(newVar)
		# 'below is deprecated - remove:			
		} else if (distr=="norm"){
			Nmeans <- newNodeParams$Norm_mean
			SDs <- newNodeParams$Norm_sd
			len_Nmeans <- length(Nmeans)
			len_SDs <- length(SDs)
			if (len_Nmeans!=1 & len_Nmeans!=Nsamp) stop("Incorrect length for the Normal means")
			if (len_SDs!=1 & len_SDs!=Nsamp) stop("Incorrect length for the Normal means")
			if (len_Nmeans==1) Nmeans <- rep.int(Nmeans, Nsamp)
			if (len_SDs==1) SDs <- rep.int(SDs, Nsamp)
			newVar <- rep.int(NA_real_, Nsamp)
			# N_notNA_samp <- sum(!is.na(Nmeans))
			newVar[!EFUP.prev] <- rnorm(n=N_notNA_samp, mean=Nmeans[!EFUP.prev], sd = SDs[!EFUP.prev])
		} else { # RUN ARBITRARY DISTR FUNCTION
			standardize_param <- function(distparam) {
				check_len <- function(param) {
					len <- length(param)
					if (len==1) {
						param <- rep.int(param, N_notNA_samp)
					} else if (len==Nsamp) {
						param <- param[!EFUP.prev]
					} else {
						stop("error while evaluating node "%+% cur.node$name %+%" expression(s): "%+%expr_str%+%".\n One of the distribution parameters evaluated to an incorrect vector length, check syntax.")
					}
					param
				}
				if (class(distparam)%in%"list") {
					distparam <- lapply(distparam, check_len)
					distparam <- do.call("cbind", distparam)
				} else if (is.vector(distparam)) {
					distparam <- check_len(distparam)
				} else if (is.matrix(distparam)) {
					if (nrow(distparam)==1) { # for mtx with 1 row -> repeat N_notNA_samp times:
						distparam <- matrix(distparam, nrow=N_notNA_samp, ncol=ncol(distparam), byrow=TRUE)	
					} else if (nrow(distparam)==Nsamp) { # for mtx with Nsamp rows -> subset mtx[!EFUP.prev,]
						distparam <- distparam[!EFUP.prev,,drop=FALSE]
					} else {
						stop("error while evaluating node "%+% cur.node$name %+%" expression(s): "%+%expr_str%+%".\n One of the distribution parameters evaluated to an incorrect vector length, check syntax.")
					}
				} else {
					# stop("...one of the distribution parameters evaluated to unsported data type...")
					stop("error while evaluating node "%+% cur.node$name %+%" expression(s): "%+%expr_str%+%".\n One of the formulas evaluated to an unsported data type, check syntax.")
				}
				distparam
			}
			# *) Check function under name distr exists
			if (!exists(distr)) {
				stop("...distribution function '"%+%distr%+% "' cannot be found...")
			}
			# *) Go over distribution parameters and for each parameter:
			# check for consistency; make it an appropriate length; turn each list parameter into matrix;
			# print("newNodeParams$dist_params"); print(newNodeParams$dist_params)
			newNodeParams$dist_params <- lapply(newNodeParams$dist_params, standardize_param)
			# print("newNodeParams$dist_params"); print(newNodeParams$dist_params)
			# *) Add n argument to dist_params
			newNodeParams$dist_params <-  append(list(n=N_notNA_samp), newNodeParams$dist_params)
			# *) Execute the function passing the distribution parameters
			newVar_Samp <- try(do.call(distr, newNodeParams$dist_params))
			if(inherits(newVar_Samp, "try-error")) {
				stop("...call to custom distribution function "%+%distr%+%"() resulted in error...")
			}
			newVar <- rep.int(NA, Nsamp)
			if (is.factor(newVar_Samp)) {
				newVar[!EFUP.prev] <- as.numeric(levels(newVar_Samp))[newVar_Samp]
				newVar <- factor(newVar)
			} else {
				newVar[!EFUP.prev] <- newVar_Samp
			}
		}
		newVar
	}
	#---------------------------------------------------------------------------------
	# Iteratively create observed DAG nodes (wide format data.fame of Nsamp observations)
	#---------------------------------------------------------------------------------
	EFUP.prev <- rep(FALSE,Nsamp)
	LTCF.prev <- rep(FALSE,Nsamp)
	obs.df <- data.frame(ID=seq(1:Nsamp))
	#---------------------------------------------------------------------------------
	# CHECKS PERFORMED DURING EVALUTION:
	#---------------------------------------------------------------------------------
	# at each node check:
	# *) (formulas) check all formulas are evaluable R expressions (try(eval))
	# *) (formulas) check each cur.node formula references:
	#	node names that already exist, and all node names must have order < cur.node$order

	#---------------------------------------------------------------------------------
	# consider pre-allocating memory for newNodeParams and newVar
	#---------------------------------------------------------------------------------
	newVar <- vector(length=Nsamp)
	NodeParentsNms <- vector("list", length=length(DAG))	# list that will  have parents' names for each node
	names(NodeParentsNms) <- sapply(DAG, '[[', "name")
	t_pts <- NULL
	for (cur.node in DAG) {
		t <- cur.node$t # define variable for a current time point t
		t_new <- !(t%in%t_pts) # set to TRUE when switch to new time point t occurs otherwise FALSE
		t_pts <- c(t_pts,t); t_pts <- as.integer(unique(t_pts)) # vector that keeps track of unique timepoints t
		gnodename <- as.character(unlist(strsplit(cur.node$name, "_"))[1])
		# dprint("current t: "%+%t%+%"; t new: "%+%t_new); dprint("current time points: ");  dprint(t_pts);
		# dprint("obs.df"); dprint(head(obs.df))
		# dprint("is null t_pts"); dprint(is.null(t_pts)); dprint(is.null(t))

		# 12/23/2014 OS: Decided to turned off imputation (carry-forward) for summary measure data (when prev.data is provided)
		# if (!is.null(t)) {	# check time points were specified by user
		# 	# When simulating in the environment of prev.data as a base (for MSM summary measures)
		# 	# need to check if the failure event has occurred at the previous timepoint when LTCF is not null
		# 	if (!is.null(prev.data) & !is.null(LTCF) & (t > t_pts[1])) { 
		# 		LTCFname <- LTCF%+%"_"%+%(t-1)
		# 		LTCF.prev <- (prev.data[,LTCFname]%in%1)
		# 	}
		# }

		#------------------------------------------------------------------------
		# CHECKS NODE DISTRIBUTIONS & EVALUATE NODE DISTRIBUTION PARAMS BASED ON NODE FORMULAS
		#------------------------------------------------------------------------
		# if !is.null(prev.data) then evalute the formula in the envir of prev.data ONLY!
		newNodeParams <- with(if (!is.null(prev.data)) prev.data else obs.df, {
			# ANCHOR_VARS_OBSDF <- TRUE
			ANCHOR_VARS_OBSDF <- list()
			# local_vec_funs <- getlocalfuns(DAG)
			# 'below is deprecated - remove:			
			if (cur.node$distr=="const") {
				eval_expr_res <- eval_nodeform(as.character(cur.node$mean), cur.node)
				list(const_val=as.numeric(eval_expr_res$evaled_expr), par.names=eval_expr_res$par.nodes)
			# 'below is deprecated - remove:			
			} else if (cur.node$distr=="unif") {
				# print(as.character(cur.node$unifmin)); print(as.character(cur.node$unifmax))
				eval_expr_res1 <- eval_nodeform(as.character(cur.node$unifmin), cur.node)
				eval_expr_res2 <- eval_nodeform(as.character(cur.node$unifmax), cur.node)
				# dprint("uniform bounds [a,b]"); dprint(head(eval_expr_res1$evaled_expr)); dprint(head(eval_expr_res2$evaled_expr))
				list(a=eval_expr_res1$evaled_expr, b=eval_expr_res2$evaled_expr, par.names=eval_expr_res1$par.nodes)
			# 'below is deprecated - remove:			
			} else if (cur.node$distr=="Bern") {
				eval_expr_res <- eval_nodeform(as.character(cur.node$prob), cur.node)
				# dprint("Binom prob"); dprint(head(eval_expr_res))
				list(Binom_prob=eval_expr_res$evaled_expr, par.names=eval_expr_res$par.nodes)
			# 'below is deprecated - remove:			
			} else if (cur.node$distr=="cat"){
				eval_expr_res <- eval_nodeform(as.character(cur.node$probs), cur.node)
				# dprint("Cat Prob"); dprint(head(eval_expr_res))
				list(Cat_prob=eval_expr_res$evaled_expr, par.names=eval_expr_res$par.nodes)
			# 'below is deprecated - remove:			
			} else if (cur.node$distr=="norm"){
				eval_expr_res1 <- eval_nodeform(as.character(cur.node$mean), cur.node)
				eval_expr_res2 <- eval_nodeform(as.character(cur.node$sd), cur.node)
				# dprint("Norm mean"); dprint(head(eval_expr_res1))
				# dprint("Norm sd"); dprint(head(sqrt(eval_expr_res2)))
				list(Norm_mean=eval_expr_res1$evaled_expr, Norm_sd=eval_expr_res2$evaled_expr, par.names=eval_expr_res1$par.nodes)
			# ADDED FOR ARBITRARY DISTRIBUTION FUNCTIONS, THIS IS THE ONLY VERSION THAT NEEDS TO BE KEPT
			# NEED TO ADDRESS: WHEN A CONSTANT (length==1) IS PASSED AS A PARAMETER, DON'T TURN IT INTO A VECTOR OF LENGTH N
			} else {
				eval_expr_res <- lapply(cur.node$dist_params, function(expr) eval_nodeform(as.character(expr), cur.node))

				# if (gnodename=="A1") {
				# 	dprint("cur.node t:"); dprint(cur.node$t)
				# 	dprint("expr:"); dprint(lapply(cur.node$dist_params, function(expr) as.character(expr)))
				# 	dprint("eval_expr_res:"); dprint(eval_expr_res)
				# 	dprint("dist_params:"); dprint(lapply(eval_expr_res, '[[' ,"evaled_expr"))
				# }
				
				# combine parents from all list items into one vector:
				par.names <- unique(unlist(lapply(eval_expr_res, '[[', "par.nodes")))
				dist_params <- lapply(eval_expr_res, '[[' ,"evaled_expr")
				# dist_params <- lapply(eval_expr_res, function(expr) expr$evaled_expr)
				list(dist_params=dist_params, par.names=par.names)
			}
		})
	
		if (!is.null(newNodeParams$par.names)) {
			NodeParentsNms[[cur.node$name]] <- newNodeParams$par.names	
		}

		#------------------------------------------------------------------------
		# SAMPLE NEW COVARIATE BASED ON DISTR PARAMS
		#------------------------------------------------------------------------
		newVar <- sampleNodeDistr(newNodeParams, cur.node$distr, EFUP.prev,  cur.node, cur.node$dist_params)

		# already performed inside sampleNodeDistr, so commented out:
		# newVar[EFUP.prev] <- NA
		# uncomment to assign 0 instead of NA for missing (after EOF=TRUE node evals to 1)
		# newVar[EFUP.prev] <- 0
		#------------------------------------------------------------------------
		# LTCF is a generic name for a failure/censoring node, after failure occurred (node=1), carry forward (impute) all future covariate values (for example, survival outcome with EFUP=TRUE)
		#------------------------------------------------------------------------
		if (!is.null(t)) {	# check time points were specified by user
			# check current t is past the first time-point & we want to last time-point carried forward (LTCF)
			if ((sum(LTCF.prev) > 0) & (t > t_pts[1]) & !is.null(LTCF)) { 
				# Carry last observation forward for those who reached EFUP (failed or but not censored)
				prevtVarnm <- gnodename%+%"_"%+%(t-1)
				# Check first that the variable exists (has been defined at the previous time point), if it doesn't exist, just assign NA
				if(!any(names(obs.df)%in%prevtVarnm)) {
					warning(gnodename%+%": is undefined at t="%+%(t-1)%+%", hence cannot be carried forward to t="%+%t)
					newVar[LTCF.prev] <- NA
				} else {
					newVar[LTCF.prev] <- obs.df[LTCF.prev, (gnodename%+%"_"%+%(t-1))]
				}
				# dprint("obs.df"); dprint(names(obs.df)); dprint(gnodename%+%"_"%+%(t-1))
			}
			# carry forward the censoring indicator as well (after evaluating to censored=1) - disabled call doLTCF() with censoring node name instead
			# if ((!is.null(LTCF))) {
			# 	if (is.EFUP(cur.node) & (!(LTCF%in%gnodename))) {
			# 		newVar[EFUP.prev & !(LTCF.prev)] <- 1
			# 	}				
			# }
		}
		#------------------------------------------------------------------------
		# modify the observed data by adding new sampled covariate
		# *** need to check new node name is legitimate (can be used in data.frame) ***
		#------------------------------------------------------------------------	
		obs.df <- within(obs.df, {assign(cur.node$name, newVar)})

		if (is.EFUP(cur.node)) { # if cur.node is EFU=TRUE type set all observations that had value=1 to EFUP.prev[indx]=TRUE
			EFUP.now <- (obs.df[,ncol(obs.df)]%in%1)
			EFUP.prev <- (EFUP.prev | EFUP.now)
			if ((!is.null(LTCF)) && (LTCF%in%gnodename) && is.null(prev.data)) { # is this node the one to be carried forward (LTCF node)? mark the observations with value = 1 (carry forward)
				LTCF.prev <- (LTCF.prev | EFUP.now)
			}
		}
	}
	# Collect all attributes to be assigned to the obs data	
    all_ts <- get_allts(obs.df) # calculate actual time values used in the simulated data
	if (sum(LTCF.prev)>0) {	# only change the LTCF attribute if outcome carry forward imputation was really carried out for at least one obs
		LTCF_flag <- LTCF
	} else {
		LTCF_flag <- NULL
	}

	newattrs <- FormAttributes(DAG=DAG, parents=NodeParentsNms, dataform="wide", LTCF=LTCF_flag, tvals=all_ts)
	attributes(obs.df) <- c(attributes(obs.df), newattrs)
	dprint("sim data"); dprint(head(obs.df, 1))
	if (!wide) {
	    if (length(all_ts)>1) {		# only perform conversion when there is more than one t in the simulated data
	    	obs.df <- DF.to.long(obs.df)
		} else {
			warning("Simulated data returned in wide format. Can't convert to long format, since only one time-point was detected.")
		}
	}
	return(obs.df)
}

#' Simulate Observed Data
#'
#' This function simulates observed data from a DAG object.
#' @param DAG A DAG objects that has been locked with set.DAG(DAG). Observed data from this DAG will be simulated.
#' @param n Number of observations to sample.
#' @param wide A logical, if TRUE the output data is generated in wide format, if FALSE, the output longitudinal data in generated in long format
#' @param LTCF The name of the right-censoring / failure event indicator variable for the Last Time-point Carried Forward imputation. By default, when LTCF is left unspecified, all variables that follow after any end of follow-up (EFU) event are set to missing (NA). The end of follow-up event occurs when a binary node declared with EFU=TRUE is observed to be equal to 1, indicating a failing or right-censoring event. To forward impute the values of the time-varying nodes after the occurrence of the EFU event, set the LTCF argument to a name of the EFU node representing this event. This implies that for each observation, missing value of a time-varying variable (that is node declared with t argument) will be replaced by the last observed value of that variable, if the missingness is a result of the EFU event of the node LTCF.
#' @param rndseed Seed for the random number generator.
#' @return A data.frame where each column is sampled from the conditional distribution specified by the corresponding \code{DAG} object node.
#' @export
simobs <- function(DAG, n, wide = TRUE, LTCF = NULL, rndseed = NULL) {
	if (!is.DAG(DAG)) stop("DAG argument must be an object of class DAG")

	simFromDAG(DAG=DAG, Nsamp=n, wide=wide, LTCF=LTCF, rndseed=rndseed)
}

#' Simulate Full Data (Using Action DAG(s))
#'
#' This function simulates full data based on a list of intervention DAGs, returning a list of \code{data.frame}s.
#' @param actions Actions specifying the counterfactual DAG. This argument must be either an object of class DAG.action or a list of DAG.action objects.
#' @param n Number of observations to sample.
#' @param wide A logical, if TRUE the output data is generated in wide format, if FALSE, the output longitudinal data in generated in long format
#' @param LTCF The name of the right-censoring / failure event indicator variable for the Last Time-point Carried Forward imputation. By default, when LTCF is left unspecified, all variables that follow after any end of follow-up (EFU) event are set to missing (NA). The end of follow-up event occurs when a binary node declared with EFU=TRUE is observed to be equal to 1, indicating a failing or right-censoring event. To forward impute the values of the time-varying nodes after the occurrence of the EFU event, set the LTCF argument to a name of the EFU node representing this event. This implies that for each observation, missing value of a time-varying variable (that is node declared with t argument) will be replaced by the last observed value of that variable, if the missingness is a result of the EFU event of the node LTCF.
#' @param rndseed Seed for the random number generator.
#' @return A named list, each item is a \code{data.frame} corresponding to an action specified by the actions argument, action names are used for naming these list items.
#' @export
simfull <- function(actions, n, wide = TRUE, LTCF = NULL, rndseed=NULL) {
# simfullData <- function(actions, n, wide = TRUE, LTCF = NULL, rndseed=NULL) {
	if (!is.null(rndseed)) {
		set.seed(rndseed)
	}
	if (("DAG.action" %in% class(actions))) {
		actname <- get.actname(actions)
		actions <- list(actions)
		names(actions) <- actname
	} else if ("list" %in% class(actions)) {
		checkDAGs <- sapply(actions, is.DAG.action)
		if (!all(checkDAGs)) stop("argument 'actions': all elements of the list must be DAG.action objects")
	} else {
		stop("argument 'actions' must be an object of class 'DAG.action' or a list of 'DAG.action' objects")
	}

	fulldf.list <- list()	# list that will contain full data (each item = one dataframe per intervention)
	for (idx_act in c(1:length(actions))) {	# loop over each action/intervention/regimen DAG
		actname <- names(actions)[idx_act]
		actDAG <- actions[[idx_act]]
		fulldf <- try(simFromDAG(DAG=actDAG, Nsamp=n, wide=wide, LTCF=LTCF, rndseed=rndseed))
		if(inherits(fulldf, "try-error")) {
			stop("simulating full data for action '"%+%actname%+%"' resulted in error...", call. = FALSE)
		}
		# adding action indicator column to the data.frame
		# newattrs <- CopyAttributes(attrslist=attributes(fulldf)) 	# save attributes
		# actindvar <- rep.int(actname, times=nrow(fulldf))
		# fulldf <- cbind(action=actindvar, fulldf)
		# attributes(fulldf) <- c(attributes(fulldf), newattrs)
		# attr(fulldf, "node_nms") <- c(actname, attr(fulldf, "node_nms"))
		# names(attr(fulldf, "node_nms"))[1] <- actname

		fulldf.list <- c(fulldf.list, list(fulldf))
	}
	if (length(actions)!=length(fulldf.list)) stop("simfull(): couldn't create separate df for each action DAG")
	names(fulldf.list) <- names(actions)
	return(fulldf.list)
}

#' Simulate Full or Observed Data from \code{DAG} Object
#'
#' This function simulates full data based on a list of intervention DAGs, returning a list of \code{data.frame}s.
#' @param DAG A DAG objects that has been locked with set.DAG(DAG). Observed data from this DAG will be simulated if actions argument is omitted.
#' @param actions Character vector of action names which will be extracted from the DAG object. Alternatively, this can be a list of action DAGs selected with \code{A(DAG)} function, in which case the argument \code{DAG} is unused. When this argument is missing, the default is to samlpe observed data from the \code{DAG} object.
#' @param n Number of observations to sample.
#' @param wide A logical, if TRUE the output data is generated in wide format, if FALSE, the output longitudinal data in generated in long format
#' @param LTCF The name of the right-censoring / failure event indicator variable for the Last Time-point Carried Forward imputation. By default, when LTCF is left unspecified, all variables that follow after any end of follow-up (EFU) event are set to missing (NA). The end of follow-up event occurs when a binary node declared with EFU=TRUE is observed to be equal to 1, indicating a failing or right-censoring event. To forward impute the values of the time-varying nodes after the occurrence of the EFU event, set the LTCF argument to a name of the EFU node representing this event. This implies that for each observation, missing value of a time-varying variable (that is node declared with t argument) will be replaced by the last observed value of that variable, if the missingness is a result of the EFU event of the node LTCF.
#' @param rndseed Seed for the random number generator.
#' @return If actions argument is missing a simulated data.frame is returned, otherwise the function returns a named list of action-specific simulated data.frames with action names giving names to corresponding list items.
#' @export
sim <- function(DAG, actions, n, wide = TRUE, LTCF = NULL, rndseed=NULL) {
	# *) check if actions argument is missing -> simulate observed data from the DAG
	# *) if actions consist of characters, try to extract those actions from the DAG and simulate full data

	# SIMULATE OBSERVED DATA FROM DAG (if no actions)
	if (missing(actions)) {	
		if (!is.DAG(DAG)) stop("DAG argument must be an object of class DAG")
		if (!is.DAGlocked(DAG)) stop("call set.DAG() before attempting to simulate data from DAG")
		message("simulating observed dataset from the DAG object")
		return(simobs(DAG=DAG, n=n, wide = wide, LTCF = LTCF, rndseed = rndseed))

	# SIMULATE FULL DATA FROM ACTION DAGs (when actions are present)
	} else {
		if (is.character(actions)) { # grab appropriate actions from the DAG by name
			if (!is.DAG(DAG)) stop("DAG argument must be an object of class DAG")
			actions <- getactions(DAG, actions)
		} else if (is.list(actions)) {
			checkDAGs <- sapply(actions, is.DAG)
			if (!all(checkDAGs)) stop("actions must be either a list of DAGs or a vector of action names")
		} else {
			stop("argument actions must be a character vector of action names or a list of action DAGs")
		}
		message("simulating action-specific datasets for action(s): "%+%paste(names(actions), collapse = " "))
		return(simfull(actions=actions, n=n, wide = wide, LTCF = LTCF, rndseed=rndseed))
	}
}

#' Imputation with Last Time Point (Observation) Carried Forward (LTCF)
#'
#' Carry forward (forward impute) all missing variable values for simulated observations that have reached the end of their follow-up, as defined by the node of type (EOF=TRUE).
#' @param data Simulated \code{data.frame} in wide format
#' @param outcome Character string specifying the outcome node that is the indicator of the end of follow-up (observations with value of the outcome variable being 1 indicate that the end of follow-up has been reached). The outcome variable must be a binary node that was declared with \code{EFU=TRUE}.
#' @return Modified simulated \code{data.frame}, forward imputed all variables after outcome switched to 1.
#' @export
doLTCF <- function(data, outcome) {
	# attrslist=attributes(data)
	DAG <- attr(data, "DAG")
	Nsamp <- nrow(data)
	LTCF.prev <- rep(FALSE,Nsamp)
	t_pts <- NULL
	cur.outcome <- FALSE
	if (is.longfmt(data)) stop("Last Timepoint Carry Forward (LTCF) can only be executed for data in wide format")
	#------------------------------------------------------------------------
	# Loop over nodes in DAG and keep track of EFUP observations in the data (already sampled)
	#------------------------------------------------------------------------
	for (cur.node in DAG) {
		t <- cur.node$t # define variable for a current time point t
		t_new <- !(t%in%t_pts) # set to TRUE when switch to new time point t occurs otherwise FALSE
		t_pts <- c(t_pts,t); t_pts <- as.integer(unique(t_pts)) # vector that keeps track of unique timepoints t
		gnodename <- as.character(unlist(strsplit(cur.node$name, "_"))[1])
		if (gnodename%in%outcome) { # if this generic node name is the outcome we need to carry forward this observation when it evaluates to 1
			cur.outcome <- TRUE
		} else {
			cur.outcome <- FALSE
		}
		if (!is.null(t)) {	# check time points were specified by user
			# check current t is past the first time-point & we want to last time-point carried forward (LTCF)
			if ((sum(LTCF.prev) > 0) & (t > t_pts[1])) { # Carry last observation forward for those who reached EFUP (outcome value = 1)
				data[LTCF.prev, cur.node$name] <- data[LTCF.prev, (gnodename%+%"_"%+%(t-1))]
			}
		}
		if  (is.EFUP(cur.node)&(cur.outcome)) { # if cur.node is EFUP=TRUE type set all observations that had value=1 to LTCF.prev[indx]=TRUE
			LTCF.prev <- (LTCF.prev | (data[,cur.node$name]%in%1))
		}
	}

	if (sum(LTCF.prev)>0) {	# only change the LTCF attribute if outcome carry forward imputation was carried out for at least one obs
		LTCF_flag <- outcome
	} else {
		LTCF_flag <- NULL
	}
	attr(data, "LTCF") <- LTCF_flag
	# newattrs <- CopyAttributes(attrslist=attrslist, LTCF=LTCF_flag) 	# save attributes from input format data
	# attributes(simdf_long) <- c(attributes(simdf_long), newattrs)
	return(data)
}

#' Convert Data from Wide to Long Format Using \code{reshape}
#'
#' This utility function takes a simulated data.frame in wide format as an input and converts it into a long format (slower compared to \code{\link{DF.to.longDT}}).
#'
#' Keeps all covariates that appear only once and at the first time-point constant (carry-forward).
#'
#' All covariates that appear fewer than range(t) times are imputed with NA for missing time-points.
#'
#' Observations with all NA's for all time-varying covariates are removed.
#' 
#' When removing NA's the time-varying covariates that are attributes (attnames) are not considered.
#'
#' @param df_wide A \code{data.frame} in wide format
#' @return A \code{data.frame} object in long format
#' @export
DF.to.long <- function(df_wide) {
# DF.to.long <- function(simdf_wide) {	
	Nsamp <- nrow(df_wide)
    all_ts <- get_allts(df_wide) # calculate actual time values used in the simulated data	
    attnames <- attr(df_wide, "attnames")
    node_nms <- attr(df_wide, "node_nms")
    node_nms_split <- strsplit(node_nms, "_")
    node_nms_vec <- sapply(node_nms_split, '[', 1)
    node_nms_unq <- unique(node_nms_vec)

    # if there are no time-points (t) attributes, then the long vs. wide format is undefined.
    if (length(all_ts)==0) return(df_wide)

	varying <- list()
	v.names <- NULL
	bsl.names <- NULL
	for (cur_node_name in node_nms_unq) {
		idx_node <- sapply(node_nms_split, function(t_nodename) t_nodename[1]%in%cur_node_name)
		count_ts <- sum(idx_node)
		node_t_vals <- unlist(sapply(node_nms_split, function(t_nodename) if(t_nodename[1]%in%cur_node_name) as.integer(t_nodename[2])))
		# if node name has no "_", assume its bsl and assign first time-point:
		if (all(is.na(node_t_vals))) node_t_vals <- all_ts[1] 

		dprint("cur_node_name: "%+%cur_node_name);
		dprint("all_ts"); dprint(all_ts)
		# dprint("idx_node"); dprint(idx_node)
		dprint("count_ts"); dprint(count_ts)
		dprint("node_t_vals"); dprint(node_t_vals)

		if (count_ts==length(all_ts)) { # the number of time-points is equal to all time-points => # everything is well defined
			varying <- c(varying, list(node_nms[idx_node]))
			v.names <- c(v.names, cur_node_name)
		} else if ((count_ts==1) & (all_ts[all_ts%in%node_t_vals][1]==all_ts[1])) { # only one time-point and its the first-one
			# node is baseline: everything is fine, rename baseline var removing the _t
			bsl.dat.name <- node_nms[which(node_nms_vec%in%cur_node_name)][1]
			bsl.names <- c(bsl.names, cur_node_name)
			if (bsl.dat.name!=cur_node_name) {
				names(df_wide)[names(df_wide) %in% bsl.dat.name] <- cur_node_name
			}
		} else { # in between 1 & 2 => need to impute to length(all_ts) filling up with NAs
			ts_to_NAs <- all_ts[!all_ts%in%node_t_vals]
			ts_not_NAs <- all_ts[all_ts%in%node_t_vals]
			NA_nodenames <- cur_node_name%+%"_"%+%ts_to_NAs # define these node names as missing and add them to df
			df_NAts <- matrix(NA, nrow=Nsamp, ncol=length(ts_to_NAs))
			colnames(df_NAts) <- NA_nodenames
			df_wide <- cbind(df_wide, df_NAts)
			all_vnames <- cur_node_name%+%"_"%+%all_ts
			varying <- c(varying, list(all_vnames))
			v.names <- c(v.names, cur_node_name)
		}
	}
	simdf_long <- reshape(data=df_wide, varying=varying, v.names=v.names, timevar = "t", times = all_ts, sep="_", direction="long")
	simdf_long <- simdf_long[order(simdf_long$ID, simdf_long$t),] # 1) long format is sorted by t first, then ID -> needs to be sorted by ID then time	
	simdf_long <- simdf_long[,-ncol(simdf_long)]  # 2) remove last column and reorder columns ID, t, ...
	if (length(attnames)>0) v.names <- v.names[!v.names%in%attnames]
	dprint("v.names"); dprint(v.names)
	# dprint("simdf_long after reshape"); dprint(simdf_long)
	simdf_long <- simdf_long[rowSums(is.na(simdf_long[,v.names]))<length(v.names),] # 3) remove last NA rows (after censoring or EFUP)
	newattrs <- CopyAttributes(attrslist=attributes(df_wide), dataform="long") 	# save attributes from input wide format data
	attributes(simdf_long) <- c(attributes(simdf_long), newattrs)
	attr(simdf_long, "v.names") <- v.names
	simdf_long
}

#' @importFrom reshape2 melt
NULL
#' @import data.table
NULL
#' Convert Data from Wide to Long Format Using \code{dcast.data.table}
#'
#' This utility function takes a simulated data.frame in wide format as an input and converts it into a long format 
#' using \pkg{data.table} package functions \code{melt.data.table} and \code{dcast.data.table}.
#'
#' Keeps all covariates that appear only once and at the first time-point constant (carry-forward).
#'
#' All covariates that appear fewer than range(t) times are imputed with NA for missing time-points.
#'
#' Observations with all NA's for all time-varying covariates are removed.
#' 
#' When removing NA's the time-varying covariates that are attributes (attnames) are not considered.
#'
#' @param df_wide A \code{data.frame} in wide format
#' @return A \code{data.table} object in long format
#' @export
DF.to.longDT <- function(df_wide) {
	# require('data.table')
	# old attributes saved
	newattrs <- CopyAttributes(attrslist=attributes(df_wide), dataform="long") 	# save attributes from input wide format data
	Nsamp <- nrow(df_wide)
    all_ts <- get_allts(df_wide) # calculate actual time values used in the simulated data	
    attnames <- attr(df_wide, "attnames")
    node_nms <- attr(df_wide, "node_nms")
    node_nms_split <- strsplit(node_nms, "_")
    node_nms_vec <- sapply(node_nms_split, '[', 1)
    node_nms_unq <- unique(node_nms_vec)
	varying <- list()
	v.names <- NULL
	bsl.names <- NULL

    dprint("all_ts"); dprint(all_ts)
    dprint("node_nms"); dprint(node_nms)
    dprint("head(df_wide)"); dprint(head(df_wide))

    # if there are no time-points (t) attributes, then the long vs. wide format is undefined.
    if (length(all_ts)==0) return(df_wide)

    #******************************************************************************************************
    # this will create a copy of the object, wont modify the original object in the calling environment
    df_wide <- data.table(df_wide)
    # !!!!! NOTE: THIS WILL convert the data.frame in the calling environment to data.table!!!!!!
    # data.table::setDT(df_wide, giveNames=TRUE, keep.rownames=FALSE)  # convert data.frame to data.table by reference (without copying)
    #******************************************************************************************************
	DF.to.longDT_run <- function(dat_df, t_pts, lvars, bslvars=NULL) {
        t_vec <- "_"%+%(t_pts)
        for (var_nm in lvars) { # one TV var at a time approach
			value_vars <- var_nm%+%t_vec
			DT_melt <- melt(dat_df, id.vars="ID", measure.vars=value_vars, variable.factor=TRUE, na.rm=FALSE)
			# DT_melt <- melt.data.table(dat_df, id.vars="ID", measure.vars=value_vars, variable.factor=TRUE, na.rm=FALSE)
			# DT_melt <- data.table::melt(dat_df, id.vars="ID", measure.vars=value_vars, variable.factor=TRUE, na.rm=FALSE)
			var_nm_rep <- rep.int(var_nm, nrow(DT_melt))
			t_rep <- rep(t_pts, each=nrow(dat_df))
			DT_melt[, c("LVname","t"):= list(var_nm_rep,t_rep)]
			DT_l <- data.table::dcast.data.table(DT_melt, t + ID ~ LVname)
			data.table::setkeyv(DT_l, c("ID", "t"))
			# data.table::setkey(DT_l, ID, t)
			if (which(lvars%in%var_nm)==1) {
				DT_l_fin <- DT_l  
			} else {
				DT_l_fin[,var_nm:=DT_l[[var_nm]], with=FALSE]
			}
        }
        if (!is.null(bslvars)) {
        	DT_l_bsl <- dat_df[,c("ID",bslvars), with=FALSE]
        	# data.table::setkey(DT_l_bsl, ID)  # needs to be sorted
        	data.table::setkeyv(DT_l_bsl, "ID")  # needs to be sorted
        	DT_l_fin <- DT_l_bsl[DT_l_fin]
        }
        DT_l_fin
	 }
	# for each node, determinine if its baseline or time-varying
	# if time-varying and columns are missing for some of its time-points => impute those time-points as NA (last ifelse)
	for (cur_node_name in node_nms_unq) {
		idx_node <- sapply(node_nms_split, function(t_nodename) t_nodename[1]%in%cur_node_name)
		count_ts <- sum(idx_node)
		node_t_vals <- unlist(sapply(node_nms_split, function(t_nodename) if(t_nodename[1]%in%cur_node_name) as.integer(t_nodename[2])))
		# if node name has no "_", assume its bsl and assign first time-point:
		if (all(is.na(node_t_vals))) node_t_vals <- all_ts[1] 
		dprint("cur_node_name: "%+%cur_node_name);
		dprint("all_ts"); dprint(all_ts)
		# dprint("idx_node"); dprint(idx_node)
		dprint("count_ts"); dprint(count_ts)
		dprint("node_t_vals"); dprint(node_t_vals)

		if (count_ts==length(all_ts)) { # the number of time-points is equal to all time-points =>  everything is well defined
			varying <- c(varying, list(node_nms[idx_node]))
			v.names <- c(v.names, cur_node_name)
		} else if ((count_ts==1) & (all_ts[all_ts%in%node_t_vals][1]==all_ts[1])) { # only one time-point and its the first-one
			# node is baseline: everything is fine, do nothing, just save its name
			bsl.dat.name <- node_nms[which(node_nms_vec%in%cur_node_name)][1]
			bsl.names <- c(bsl.names, cur_node_name)
			if (bsl.dat.name!=cur_node_name) {
				setnames(df_wide, bsl.dat.name, cur_node_name)
			}
		} else { # in between 1 & 2 => need to impute to length(all_ts) filling up with NAs
			ts_to_NAs <- all_ts[!all_ts%in%node_t_vals]
			ts_not_NAs <- all_ts[all_ts%in%node_t_vals]
			NA_nodenames <- cur_node_name%+%"_"%+%ts_to_NAs # define these node names as missing and add them to df
			df_wide[, NA_nodenames:=NA, with=FALSE]
			all_vnames <- cur_node_name%+%"_"%+%all_ts
			varying <- c(varying, list(all_vnames))
			v.names <- c(v.names, cur_node_name)
		}
	}
	dprint("v.names"); dprint(v.names)
	dprint("bsl.names"); dprint(bsl.names)
	#*** the baseline variable names are also passed as last arg
	simDT_long <- DF.to.longDT_run(dat_df=df_wide, t_pts=all_ts, lvars=v.names, bslvars=bsl.names)
	if (length(attnames)>0) v.names <- v.names[!v.names%in%attnames]
	dprint("v.names after rem attrs"); dprint(v.names)
	simDT_long <- simDT_long[rowSums(is.na(simDT_long[,v.names, with=FALSE]))<length(v.names),] # 3) remove last NA rows (after censoring or EFUP)
	attributes(simDT_long) <- c(attributes(simDT_long), newattrs)
	attr(simDT_long, "v.names") <- v.names
	simDT_long
}

# NOT IMPLEMENTED
# will convert the dataset back to wide format from long, get the necessary attributes from simdf_long
# convert_to_wide <- function(simdf_long) {
# 	# Nsamp <- nrow(df_wide)
#     # all_ts <- get_allts(simdf_long) # calculate actual time values used in the simulated data	
#     attnames <- attr(simdf_long, "attnames")
#     node_nms <- attributes(simdf_long)$names[-1]
#     # node_nms_split <- strsplit(node_nms, "_")
#     # node_nms_unq <- unique(sapply(node_nms_split, '[', 1))
# 	varying <- list()
# 	v.names <- NULL
# 	simdf_wide <- reshape(data=simdf_long, idvar=, varying=varying, v.names=v.names, timevar = "t", times = all_ts, sep="_", direction="wide")
# 	simdf_wide
# }












