## Smoothed average using weighted mean

#load libraries
library(data.table)
library(ggplot2)
library(tidyverse)
library(mgcv)
library(lubridate)
library(cowplot)
library(zoo)

#set cowplot theme
theme_set(cowplot::theme_cowplot(font_size = 10) + theme(strip.background = element_blank()))

#set data path
data_path <-"C:\\Users\\emiel\\Documents\\LSHTM\\Fellowship\\Project\\comix_mobility\\Data\\"

#import contact data
cnts <- qs::qread(file.path(data_path, "part_cnts.qs"))

#filter out participants of a certain age
cnts <- cnts[part_age >= 18 & part_age <= 65]

#order by date
cnts_date <- cnts[order(date)]

#create data table with subset of variables
num <- cnts_date[, .(date, part_id, part_age, survey_round, weekday, day_weight, home = n_cnt_home, 
                     work = n_cnt_work, school = n_cnt_school, other = n_cnt_other)]
num[, t := as.numeric(date - ymd("2020-01-01"))]

#create study column
num[, study := "CoMix"]

#create sequence of dates
date <- seq(as.Date("2020-03-02"), as.Date("2022-03-02"), by = "days")
lockdowns <- as.data.table(as.Date(date))
lockdowns$lockdown_status <- 0
colnames(lockdowns) <- c("date", "status")

#create time intervals for different types of restrictions
T1 <- interval(ymd("2020-03-02"), ymd("2020-03-22"))
L1 <- interval(ymd("2020-03-23"), ymd("2020-05-31"))
T2 <- interval(ymd("2020-06-01"), ymd("2020-07-04"))
F1 <- interval(ymd("2020-07-05"), ymd("2020-09-13"))
T3 <- interval(ymd("2020-09-14"), ymd("2020-11-04"))
L2 <- interval(ymd("2020-11-05"), ymd("2020-12-01"))
T4 <- interval(ymd("2020-12-02"), ymd("2021-01-05"))
L3 <- interval(ymd("2021-01-06"), ymd("2021-03-07"))
T5 <- interval(ymd("2021-03-08"), ymd("2021-07-18"))
F2 <- interval(ymd("2021-07-19"), ymd("2022-03-02"))

#assign value to each type of restriction
lockdowns$status <- ifelse(ymd(lockdowns$date) %within% T1, 1, 
                           ifelse(ymd(lockdowns$date) %within% L1, 2, 
                           ifelse(ymd(lockdowns$date) %within% T2, 1, 
                           ifelse(ymd(lockdowns$date) %within% T3, 1, 
                           ifelse(ymd(lockdowns$date) %within% L2, 2, 
                           ifelse(ymd(lockdowns$date) %within% T4, 1, 
                           ifelse(ymd(lockdowns$date) %within% L3, 2, 
                           ifelse(ymd(lockdowns$date) %within% T5, 1, 0))))))))

#create factor
lockdown_fac <- factor(lockdowns$status, levels = c(0, 1, 2, 3),
                       labels = c("No restrictions", "Some restrictions",
                                  "Lockdown", "Pre-Pandemic"))
lockdowns$status <- lockdown_fac

#merge contact data and lockdown information
cnts_l <- merge(num, lockdowns, by = "date", all.y = F)

#import edited polymod data
pnum <- qs::qread(file.path(data_path, "polymod.qs"))

#create study column
pnum[, study := "POLYMOD"]

#add information for lockdown status (i.e. none)
pnum[, status := "Pre-Pandemic"]

#add weighting to polymod data
pnum[, weekday := lubridate::wday(date, label = T, abbr = F)]
pnum[, day_weight := ifelse(weekday == "Saturday", 2/7, 
                            ifelse(weekday == "Sunday", 2/7, 5/7))]

#bind the rows together
num <- rbind(cnts_l, pnum, fill = TRUE)

#remove participants of certain age from POLYMOD
num <- rbind(
  num[study == "CoMix"],
  num[study == "POLYMOD" & part_age >= 18 & part_age <= 65]
)

#create second database which shifts the survey rounds and dates
num2 <- rlang::duplicate(num)
num2[, date := date + 7]
num2[, survey_round := survey_round + 1]

#merge the two 
num_merge <- rbind(num, num2) 
  
#get weighted means by date 
weighted_date <- num_merge[, .(study, status, 
                               work = weighted.mean(work, day_weight),
                               home = weighted.mean(home, day_weight),
                               other = weighted.mean(other, day_weight)),
                           by = .(week = paste(year(date), "/", week(date)))]  
weighted_date <- unique(weighted_date)

#get mean of polymod data so there is one baseline point
poly <- weighted_date[study == "POLYMOD"]
poly <- poly[, .(week = 0, study, status, 
                 work = mean(work, na.rm = T),
                 home = mean(work, na.rm = T),
                 other = mean(other, na.rm = T))]
poly <- unique(poly)
weighted_date <- weighted_date[study == "CoMix"]
weighted_date <- rbind(weighted_date, poly)

# #get weighted means by survey round to compare
# weighted_round <- num_merge[, .(work = weighted.mean(work, day_weight),
#                                home = weighted.mean(home, day_weight),
#                                school = weighted.mean(school, day_weight),
#                                other = weighted.mean(other, day_weight)),
#                            by = .(round = ifelse(study == "CoMix",
#                                                  survey_round,
#                                                  paste(year(date), "/",
#                                                        week(date))))]  

#import mobility data
mob <- qs::qread(file.path(data_path, "google_mob.qs"))

#subset for same date range
mob_sub <- mob[date >= "2020-03-23" & date <= "2022-03-02"]

#duplicate google mobility data and rename columns
gm2 <- rlang::duplicate(mob_sub)
names(gm2) <- str_replace(names(gm2), "_percent_change_from_baseline", "")
names(gm2) <- str_replace(names(gm2), "_and", "")

#turn mobility data into decimals instead of percentages
gm2[, retail_recreation := (100 + retail_recreation) * 0.01]
gm2[, grocery_pharmacy  := (100 + grocery_pharmacy ) * 0.01]
gm2[, parks             := (100 + parks            ) * 0.01]
gm2[, transit_stations  := (100 + transit_stations ) * 0.01]
gm2[, workplaces        := (100 + workplaces       ) * 0.01]
gm2[, residential       := (100 + residential      ) * 0.01]
gm2[, study := "CoMix"]

#add mobility to polymod dates
pnum2 <- pnum[, .(study, date, retail_recreation = 1, grocery_pharmacy = 1, parks = 1,
                  transit_stations = 1, workplaces = 1, residential = 1)]
gm2 <- gm2[, .(date, study, retail_recreation, grocery_pharmacy, parks, 
               transit_stations, workplaces, residential)]
gm2$date <- as.Date(gm2$date)
gm2 <- rbind(gm2, pnum2)

#get means for google mobility data
gm <- gm2[, .(workplaces = mean(workplaces),
              residential = mean(residential),
              retail = mean(retail_recreation), 
              grocery = mean(grocery_pharmacy), 
              transit = mean(transit_stations),
              parks = mean(parks)),
          by = .(week = ifelse(study == "CoMix",
                               paste(year(date), "/", week(date)),
                               rep(0, length(date))), study)]

#merge
mob_cnt <- merge(weighted_date, gm, by = c("week", "study"))

#scale data by POLYMOD data point 
mob_cnt <- mob_cnt[order(week)]
mob_cnt <- mob_cnt[, .(week, study, status, work, home, other,
                       workplaces, residential, retail, grocery, transit, parks,
                       work_frac = work/head(work, 1),
                       home_frac = home/head(home, 1), 
                       other_frac = other/head(other, 1))]

##work data

#model using GAM
model <- gam(work_frac ~ s(workplaces), family = gaussian, data = mob_cnt)

#predict using 'new' data
work_f <- data.table(workplaces = seq(0, 1.25, by = 0.01));
work_f[, work := pmax(0.0, predict(model, work_f, type = "response"))]

#plot
plw <- ggplot(mob_cnt) + 
  geom_point(aes(x = workplaces, y = work_frac, colour = status)) + 
  geom_line(data = work_f, aes(x = workplaces, y = work)) +
  ylim(0, 1) + xlim(0, 1) +
  labs(x = "Google Mobility\n'workplaces' visits",
       y = "Number of Work Contacts", colour = "Status") 
plw

#plot without GAM
plw <- ggplot(mob_cnt) + 
  geom_point(aes(x = workplaces, y = work_frac, colour = status)) + 
  ylim(0, 1) + xlim(0, 1) +
  labs(x = "Google Mobility\n'workplaces' visits",
       y = "Proportion of pre-pandemic\ncontacts", colour = "Status") 
plw

##other data

#create predictor from weighting of variables
mob_cnt[, predictor := retail * 0.345 + transit * 0.445 + grocery * 0.210] # See "optimisation" below for how this was arrived at

#model using GAM
model <- gam(other_frac ~ s(predictor), family = gaussian, data = mob_cnt)

#predict using 'new' data
other_f <- data.table(predictor = seq(0, 1.25, by = 0.01));
other_f[, other := pmax(0.0, predict(model, other_f, type = "response"))]

#plot
plo <- ggplot(mob_cnt) + 
  geom_point(aes(x = predictor, y = other_frac, colour = status)) + 
  geom_line(data = other_f, aes(x = predictor, y = other)) +
  xlim(0, 1) + ylim(0, 1) + 
  labs(x = "Google Mobility weighted 'transit stations',\n'retail and recreation', and 'grocery and pharmacy' visits", 
       y = "Proportion of pre-pandemic\ncontacts", colour = "Status")
plo

#plot without GAM
plo <- ggplot(mob_cnt) + 
  geom_point(aes(x = predictor, y = other_frac, colour = status)) +
  xlim(0, 1) + ylim(0, 1) + 
  labs(x = "Google Mobility weighted 'transit stations',\n'retail and recreation', and 'grocery and pharmacy' visits", 
       y = "Proportion of pre-pandemic\ncontacts", colour = "Status")
plo
