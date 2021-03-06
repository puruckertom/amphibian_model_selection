#check to make sure required packages are installed
list.of.packages <- c("fitdistrplus","ggplot2","GLDEX","truncnorm")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages)>0) {install.packages(new.packages)}

library(fitdistrplus)
library(ggplot2)
library(GLDEX)
library(truncnorm)

#tom epa laptop home
if(Sys.info()[4]=="LZ2626UTPURUCKE"){
  ams_dir <- "c:/git/amphibian_model_selection/"
}

#subdirectories
ams_dir_input <- paste(ams_dir, "data_in/", sep = "")
ams_dir_output <- paste(ams_dir, "data_out/", sep = "")
ams_dir_graphics <- paste(ams_dir, "graphics/", sep = "")

# simulations for each generation
nsims <- 10000

#load in observational body burdens
tr_observations_covars_filename <- "tr_observations_w_covars.csv"
tr_observations_abc <- read.csv(file = paste(ams_dir_output, tr_observations_covars_filename, sep = ""), header = TRUE)
colnames(tr_observations_abc)

# experimental soil concentrations
# use when available, otherwise a function of application rate
soil_concs <- tr_observations_abc$soil_conc_ugg
#change this to equation from Weir which gives 11.2 for 1 lb/ac
#soil concentration from 1 lb/acre application (112 mg/m2), mixed evenly 1 cm depth, contact top mm
#original soil concs are in ug/g, convert to /m2
soil_concs[which.na(soil_concs)] <- 11.2

#calculate permeability coefficients based on logkow and molecular weight, cm/hr
#walker et al 2003 eq 4 for organics except phenols and aliphatic aldohols
logKow <- tr_observations_abc$LogP_pred
mol_weight <- tr_observations_abc$MolWeight
tr_observations_abc$kp <- 10^(-2.72 + (0.71 * logKow) - (0.0061 * mol_weight))
kp <- tr_observations_abc$kp
hl_hours <- exp(tr_observations_abc$BioDeg_LogHalfLife_pred)*24

#calculate dermal surface area based on body weight
bw_amphib <- tr_observations_abc$body_weight_g
namphibs <- length(bw_amphib)

#assign exposure duration
dat <- tr_observations_abc$exp_duration
hist(dat)

# tissue concentration observations
amphib_concs <- tr_observations_abc$tissue_conc_ugg

#create matrix to accept the sums of absoulte differences for each simulation in each gneration
# 20 generations by 10000 sims
dermal_sum_abs_differences <- matrix(data=NA, nrow=20, ncol=nsims)

##################################################################
### INITIAL Generation
generation = 1

# tracker for proportion of underpredicted concentrations for a generation
prop_underpredict <- vector(mode="numeric", length=nsims)

#uncertain parameters
#dermal thickness
dt_amphib <- runif(nsims, min=0.001, max=0.003)

#poisson movement rate
movement_mean <- runif(nsims, min=0.001, max=10)
movement_rate <- vector(mode="numeric", length=nsims)
for(i in 1:nsims){
  movement_rate[i] <- rpois(1,movement_mean[i])+1 #+1 since they occupy a patch when they dont move
}
bioavail <- runif(nsims, min = 0.01, max=0.21)

#create matrix namphib rows and nsim columns
dermal_dose_amphib <- matrix(data=NA, nrow=namphibs, ncol=nsims)

#allometric relationship for surface area
dermal_sa_slope <- runif(nsims, min=1.131, max=11.003)
dermal_sa_exponent <- runif(nsims, min=0.579, max=0.6112)

#fraction of dermal surface area exposed
dermal_fraction <- runif(nsims, min=0.1, max=0.5)

#create blank generation table to remember summary stats and distribution moments
generation_moments <- matrix(data=NA,nrow=20,ncol=15)
colnames(generation_moments) <- c("gen","prop_underpredict_mean","dt_mean","dt_sd","movement_rate_mean","movement_rate_sd","bioavail_mean","bioavail_sd",
                                  "dermal_sa_slope_mean","dermal_sa_slope_sd","dermal_sa_exponent_mean","dermal_sa_exponent_sd",
                                  "dermal_fraction_mean","dermal_fraction_sd","score_median")

#remember uniform limits, after generation 1 everything is poisson or normal
generation_moments[1,3] = 0.001 #update_dt_amphib$estimate[1]/1000
generation_moments[1,4] = 0.003 #update_dt_amphib$estimate[2]/1000
generation_moments[1,5] = 0.001 #update_movement_rate$estimate
generation_moments[1,6] = 10 #update_movement_rate$estimate #kept poisson sd because it was uniform in first gen
generation_moments[1,7] = 0.01 #update_bioavail$estimate[1]
generation_moments[1,8] = 0.21 #update_bioavail$estimate[2]
generation_moments[1,9] = 1.131 #update_dermal_sa_slope$estimate[1]
generation_moments[1,10] = 11.003 #update_dermal_sa_slope$estimate[2]
generation_moments[1,11] = 0.579 #update_dermal_sa_exponent$estimate[1]
generation_moments[1,12] = 0.6112 #update_dermal_sa_exponent$estimate[2]
generation_moments[1,13] = 0.1 #update_dermal_fraction$estimate[1]
generation_moments[1,14] = 0.5 #update_dermal_fraction$estimate[2]

#calculate tissue residues
# movement_rate[i] + 1 is for initial position
#vectorization for speed
for(i in 1:nsims){
  dt_amphib_iteration <- rep(dt_amphib[i],namphibs)
  movement_rate_iteration <- rep((movement_rate[i]),namphibs)
  soil_concs_degradation <- -(log(2)/hl_hours*dat/movement_rate_iteration)
  bioavailability_iteration <- rep(bioavail[i],namphibs)
  dermal_sa_slope_iteration <- rep(dermal_sa_slope[i],namphibs)
  dermal_sa_exponent_iteration <- rep(dermal_sa_exponent[i],namphibs)
  dsa_amphib <- dermal_sa_exponent_iteration * bw_amphib^dermal_sa_exponent_iteration
  dermal_fraction_iteration <- rep(dermal_fraction[i],namphibs)
  dermal_dose_amphib[,i] <- (soil_concs^soil_concs_degradation * kp * (dsa_amphib/dt_amphib_iteration) * dermal_fraction_iteration * 
                               bioavailability_iteration)/bw_amphib
  dermal_sum_abs_differences[generation,i] <- sum(abs(dermal_dose_amphib[,i] - amphib_concs))
  prop_underpredict[i] <- sum(dermal_dose_amphib[,i]<amphib_concs)/namphibs
}

prop_underpredict_mean <- mean(prop_underpredict)

# create the cbind matrix of inputs and fit scores
# this matrix is nsims rows
scores_inputs <- matrix(c(dermal_sum_abs_differences[generation,],prop_underpredict,dt_amphib,movement_rate,bioavail,
                          dermal_sa_slope,dermal_sa_exponent, dermal_fraction),nrow=10000,ncol=8,byrow = FALSE)
dim(scores_inputs)
colnames(scores_inputs) <- c("score","prop_underpredict","dt_amphib","movement_rate","bioavail",
                             "dermal_sa_slope","dermal_sa_exponent","dermal_fraction")
head(scores_inputs)

# sort by score and take the top 25%
winners_2500 <- as.data.frame(scores_inputs[order(scores_inputs[,1], decreasing = FALSE),][1:2500,])
#View(winners_2500)
dim(winners_2500)
colnames(winners_2500)

# update input distributions and plot them
hist(winners_2500$dt_amphib)
update_dt_amphib <- fitdist(winners_2500$dt_amphib*1000, "norm") #*1000 due to precision issues
hist(winners_2500$movement_rate)
update_movement_rate <- fitdist(winners_2500$movement_rate, "pois")
hist(winners_2500$bioavail)
update_bioavail <- fitdist(winners_2500$bioavail, "norm")
hist(winners_2500$dermal_sa_slope)
update_dermal_sa_slope <- fitdist(winners_2500$dermal_sa_slope, "norm")
hist(winners_2500$dermal_sa_exponent)
update_dermal_sa_exponent <- fitdist(winners_2500$dermal_sa_exponent, "norm")
hist(winners_2500$dermal_fraction)
update_dermal_fraction <- fitdist(winners_2500$dermal_fraction, "norm")

#find the median of the 2500 as the criterion for the next round
hist(winners_2500$score)
gen_score_median <- median(winners_2500$score)

#store the updated parameters by generation
generation_moments[generation,1] = generation
generation_moments[generation,2] = prop_underpredict_mean
generation_moments[generation+1,3] = update_dt_amphib$estimate[1]/1000
generation_moments[generation+1,4] = update_dt_amphib$estimate[2]/1000
generation_moments[generation+1,5] = update_movement_rate$estimate
generation_moments[generation+1,6] = update_movement_rate$estimate #kept poisson sd because it was uniform in first gen
generation_moments[generation+1,7] = update_bioavail$estimate[1]
generation_moments[generation+1,8] = update_bioavail$estimate[2]
generation_moments[generation+1,9] = update_dermal_sa_slope$estimate[1]
generation_moments[generation+1,10] = update_dermal_sa_slope$estimate[2]
generation_moments[generation+1,11] = update_dermal_sa_exponent$estimate[1]
generation_moments[generation+1,12] = update_dermal_sa_exponent$estimate[2]
generation_moments[generation+1,13] = update_dermal_fraction$estimate[1]
generation_moments[generation+1,14] = update_dermal_fraction$estimate[2]
generation_moments[generation+1,15] = gen_score_median

##################################################################
### qa type visuals
#visual check on predictions and ratios
hist(dermal_dose_amphib[,1]/amphib_concs) #ratios for first frog
head(dermal_dose_amphib[,1]) #predictions for first frog
head(amphib_concs)
head(dermal_dose_amphib[,2]) #predictions for second frog
head(sort(dermal_dose_amphib[,1]/amphib_concs,decreasing=T))
head(sort(dermal_dose_amphib[,1]/amphib_concs,decreasing=F))
head(sort(dermal_dose_amphib[,2]/amphib_concs,decreasing=T))
head(sort(dermal_dose_amphib[,1]/amphib_concs,decreasing=F))
#View(dermal_dose_amphib)

#visual check on absolute differencs
hist(dermal_sum_abs_differences)
head(dermal_sum_abs_differences[generation,])

#visual on underpredictions
hist(prop_underpredict)
#the scores of the best and the worst simulations
head(sort(dermal_sum_abs_differences[generation,],decreasing=F))
head(sort(dermal_sum_abs_differences[generation,],decreasing=T))

#find the median of the 2500 as the criterion for the next round
hist(winners_2500$score)
median(winners_2500$score)

##################################################################
### NEXT Generation
generation = 2
generation_moments[generation,1] = generation

nsims = 10000

#draw from updated distributions
CN2<-rtruncnorm(nsims, min(sim_pars_2$CN2), max(sim_pars_2$CN2), mean = -0.03060313, sd = 0.16970975)

#You have already done 50k simulations from the uniform priors. We are going to take the first 10k (not the best 10k, do not sort) of these as the first generation of simulations. We are simply throwing away the last 40k and not using them for the official simulations for the manuscript. This is necessary to honor the assumptions behind ABC-MC.
#Calculate the average of the 3 nses for each of the 10k simulations: nse_average = mean(nse_conc, nse_flow, nse_ flux)
#Take the top 2.5k simulations based on the nse_average, disregarding the other 7.5K simulations.
#Use the 2.5k set of inputs associated with these top 2.5k simulations. Calculate the unweighted kernel densities using the kde package and fit to a normal distribution, truncate at the range limits for each parameter.
#Find the first_quartile_average_nse of the original 10k nse_averages, this will be the average of the 2500 and 2501st highest average_nse of the first 10k of generation zero.

#These steps are only for generation 1 of the simulation sets, this approach is slightly different than above for generation zero.
#6.	Use the truncated normal distributions from 4) to set up the next round of simulations. Simulate with these inputs. For each simulation, calculate the average_nse. We will only keep individual simulations if the average_nse is higher that the first_quartile_average_nse (calculated in step 5) from the last set of simulations. 
#7.	Keep simulating until we get 10k new simulations with an average_nse greater than the first_quartile_average_nse from step 5 calculated for the previous set of 10k simulation results. You can make this decision of which ones to keep on the hpc server or afterwards after doing a bunch of simulations.
#8.	Calculate the updated unweighted kernel densities based on these new 10k simulations and fit to the normal distribution, truncate at the original range limits for each parameter.
#9.	Now use these new 10k simulations to calculate the updated first_quartile_average_nse, this will be the average of the 2500 and 2501st highest average_nse.
#These steps are for generations 2 . N of the simulation sets, this approach is slightly different than for generations zero and 1.
#10.	Use the truncated normal distributions from the previous generation of simulations to set up the next round of simulations. Simulate with these inputs. For each simulation, calculate the average_nse. We will only keep individual simulations if the average_nse is higher that the first_quartile_average_nse from the last set of simulations. 
#11.	Keep simulating until we get 10k new simulations with an average_nse greater than the first_quartile_average_nse calculated for the previous set of 10k simulation results.  You can make this decision of which ones to keep on the hpc server or afterwards after doing a bunch of simulations. Note that this may require more than 50k simulations to get the needed 10k good simulations.
#12.	Calculate the updated unweighted kernel densities based on the latest set of 10k simulations and fit to the normal distribution, truncating at the original range limit.
#13.	Calculate the updated first_quartile_average_nse for the new set of 10k simulations, this will be the average of the 2500 and 2501st highest average_nse.
#14.	Repeat steps 10)-13) over and over until the median_average_nse fails to improve by X% versus the median_average_nse from the last generation. We have not explicitly defined what this percentage is just yet. It will probably be something like 1% or less.
