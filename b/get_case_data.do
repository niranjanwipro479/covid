/* Get the most up to date case data
data source: www.covid19india.org
direct links to api: https://api.covid19india.org/

1. Retrieve post-April 27 district-day data
2. Create covid-LGD district keys
3. Standardize all data to LGD districts
*/

/* define lgd matching programs */
qui do $ddl/covid/covid_progs.do
qui do $ddl/tools/do/tools.do

/****************************************************/
/* 1. Retrieve the post-April 27 district case data */
/****************************************************/
cd $ddl/covid

/* define the url and pull the data files from covid19india */
pyfunc retrieve_covid19india_all_district_csv("https://api.covid19india.org/csv/latest/districts.csv", "$tmp"), i(from retrieve_case_data import retrieve_covid19india_all_district_csv) f("$ddl/covid/b")
// pyfunc retrieve_covid19india_all_district_csv("https://api.covid19india.org/v4/data-all.json", "$tmp"), i(from retrieve_case_data import retrieve_covid19india_all_district_data) f("$ddl/covid/b")

/* read in the data */
insheet using $tmp/covid19india_district_data_new.csv, clear

/* replace delhi district with missing because this is really state level data */
replace district = "" if state == "Delhi" & district == "Delhi"

/* create date object from date string */
gen date2 = date(date, "YMD")
drop date
ren date2 date
format date %td
drop if mi(date)

/* drop the few datapoints before April 27, these are data entry errors */
drop if date <= 22031
sort state district date

/* ensure states are consistent across all entries */
replace state = lower(state)
replace district = lower(district)

/* unknown state codes */
replace state = "" if state == "un"

/* drop the state totals to ensure our dataset is unique on state-district
   without state totals mixed into the long district data */
drop if state == "tt"

/* fix Daman and Diu State names */
replace state = "daman and diu" if (district == "daman") & (state == "dadra and nagar haveli and daman and diu")
replace state = "daman and diu" if (district == "diu") & (state == "dadra and nagar haveli and daman and diu")
replace state = "dadra and nagar haveli" if (district == "dadra and nagar haveli") & (state == "dadra and nagar haveli and daman and diu")

/* replace unknown or unclassified districts with missing */
replace district = "" if district == "unknown"
replace district = "" if district == "other"
replace district = "" if district == "others"
replace district = "" if district == "ndrf-odrf"
replace district = "" if district == "bsf camp"
replace district = "" if district == "unassigned"
replace district = "" if district == "airport quarantine"
replace district = "" if district == "other state"
replace district = "" if district == "others state"
replace district = "" if district == "other states"
replace district = "" if district == "foreign evacuees"
replace district = "" if district == "other region"
replace district = "" if district == "italians"
replace district = "" if district == "evacuees"
replace district = "" if district == "railway quarantine"
replace district = "" if district == "capf personnel"
replace district = "" if district == "state pool"

/* replace one incorrect state */
replace state = "bihar" if state == "assam" & district == "kishanganj"

/* rename variables to clarify meaning */
ren deceased death_total
ren confirmed cases_total

/* drop unneeded variables */
keep date state district cases_total death_total

/* correct internally inconsistent district names */
synonym_fix district, synfile($ddl/covid/b/str/cov19india_district_fixes.txt) replace

/* fill in not reported districts */
replace district = "not reported" if mi(district)
replace state = "not reported" if mi(state)

/* collapse to district level */
collapse (sum) cases_total death_total, by(state district date)

/* make it square */
egen dgroup = group(state district)
fillin date dgroup 

/* fill in state, district, lgd names within dgroup 
   to install xfill: net install xfill */
xfill state district, i(dgroup)
sort dgroup date
drop dgroup _fillin

/* fill in the missing death and cases values with 0 (these are from preceding dates with no cases reported) */
replace death_total = 0 if mi(death_total)
replace cases_total = 0 if mi(cases_total)

/* save data */
save $tmp/covid19india_raw_data, replace

/* keep only states and districts to create the covid-lgd key */
keep state district

/* drop if missing district */
drop if district == "not reported"
duplicates drop

/* save the state and district list */
sort state district
save $covidpub/covid/covid19india_state_district_list, replace

/****************************/
/* 2. Create covid-LGD keys */
/****************************/
/* import the lgd keys to match to */
use $keys/lgd_district_key, clear

/* generate ids */
gen idu = lgd_state_name + "=" + lgd_district_name

/* save for the merge */
save $tmp/lgd_fmm, replace

/* 3a. pre-April 27 data */
use $covidpub/covid/covid19india/preApr27_2020/all_old_covid19_key, clear

/* gen covid state and district */
gen covid_state_name = state
gen covid_district_name = district

/* clean state and district names */
lgd_state_clean covid_state_name
lgd_dist_clean covid_district_name

/* match to lgd-pc11 key */
lgd_state_match state

/* generate id for masala merge */
gen idm = lgd_state_name + "=" + lgd_district_name

/* run masala merge */
masala_merge lgd_state_name using $tmp/lgd_fmm, s1(lgd_district_name) idmaster(idm) idusing(idu) minbigram(0.2) minscore(0.6) outfile($tmp/covindia_lgd_district)

/* keep only master and match data */
keep if match_source < 6

/* save the key */
keep covid_state_name covid_district_name lgd_state_id lgd_district_id lgd_district_name_using
ren lgd_district_name_using lgd_district_name
save $tmp/old_covid19_lgd_district_key, replace

/* 3b. post-April 27 data */
use $covidpub/covid/covid19india_state_district_list, clear

/* gen covid state and district */
gen covid_state_name = state
gen covid_district_name = district

/* clean state and district names */
lgd_state_clean covid_state_name 
lgd_dist_clean covid_district_name

/* match to lgd-pc11 key */
lgd_state_match state

/* generate id for masala merge */
gen idm = lgd_state_name + "=" + lgd_district_name

/* run masala merge */
masala_merge lgd_state_name using $tmp/lgd_fmm, s1(lgd_district_name) idmaster(idm) idusing(idu) minbigram(0.2) minscore(0.6) outfile($tmp/covid19india_lgd_district)

/* keep only master and match data */
/* 4 districts unmatched - these don't exist in the lgd district key */
keep if match_source < 6

/* save the key */
keep covid_state_name covid_district_name lgd_state_id lgd_district_id lgd_district_name_using
ren lgd_district_name_using lgd_district_name
save $tmp/covid19india_lgd_district_key, replace

/*********************************/
/* 3. Standardize all covid data */
/*********************************/
use $covidpub/covid/covid19india/preApr27_2020/all_old_covid19_data, clear

/* merge in lgd states */
ren state lgd_state_name
merge m:1 lgd_state_name using $keys/lgd_state_key, keep(match master)
replace lgd_state_name = "not reported" if mi(lgd_state_name)
drop _merge

/* merge in lgd districts */
ren district covid_district_name
merge m:1 lgd_state_id covid_district_name using $tmp/old_covid19_lgd_district_key, keep(match master) keepusing(lgd_state_id lgd_district_id lgd_district_name)

/* check that all districts not matched from the source data are missing */
qui count if _merge == 1 & !mi(lgd_district_name)
local unmatched_districts = `r(N)'
if `unmatched_districts' > 0 {
  disp_nice "`unmatched_districts' districts unmatched in the pre-April 27 case data. These districts must be matched to LGD before proceeding."
  exit 9
}
drop _merge

/* clarify missing districts as not reported */
replace lgd_district_name = "not reported" if mi(lgd_district_name)

/* make it square */
egen dgroup = group(lgd_state_name lgd_district_name)
fillin date dgroup 

/* set as time series with dgroup */
sort dgroup date
by dgroup: egen day_number = seq()

/* fill in state, district, lgd names within dgroup 
   to install xfill: net install xfill */
xfill lgd_state_name lgd_district_name lgd_state_id lgd_district_id, i(dgroup)

/* create cumulative sums of deaths and infections */
sort dgroup day_number

/* fill in missing total death and total cases with 0- these are days preceding the first reports for a given district */
replace cases_total = 0 if mi(cases_total)
replace death_total = 0 if mi(death_total)

/* save old covid19 data */
save $tmp/old_covid19_matched_data, replace

/* covid19india data */
use $tmp/covid19india_raw_data, clear
ren state lgd_state_name

/* merge in lgd states */
merge m:1 lgd_state_name using $keys/lgd_state_key.dta, keep(match master)
replace lgd_state_name = "not reported" if mi(lgd_state_name)
drop _merge

/* merge in lgd districts */
ren district covid_district_name
merge m:1 lgd_state_id covid_district_name using $tmp/covid19india_lgd_district_key, keep(match master) keepusing(lgd_state_id lgd_district_id lgd_district_name)

/* check that all districts not matched from the source data are missing */
qui count if _merge == 1 & !mi(lgd_district_name)
local unmatched_districts = `r(N)'
if `unmatched_districts' > 0 {
  disp_nice "`unmatched_districts' districts unmatched in the post-April 27 case data. These districts must be matched to LGD before proceeding."
  exit 9
}
drop _merge

/* clarify missing districts as not reported 
   note: two reported districts in jammu and kashmir are not represented in LGD (muzaffarabad and mirpir), for now we put them under "not reported" */
replace lgd_district_name = "not reported" if mi(lgd_district_name)

/* make it square */
egen dgroup = group(lgd_state_name lgd_district_name)
fillin date dgroup 

/* set as time series with dgroup */
sort dgroup date
by dgroup: egen day_number = seq()

/* fill in state, district, lgd names within dgroup 
   to install xfill: net install xfill */
xfill lgd_state_name lgd_district_name lgd_state_id lgd_district_id, i(dgroup)

/* create cumulative sums of deaths and infections */
sort dgroup day_number

/* fill in missing total death and total cases with 0- these are days preceding the first reports for a given district */
replace cases_total = 0 if mi(cases_total)
replace death_total = 0 if mi(death_total)

/* append covindia data */
append using $tmp/old_covid19_matched_data

/* sum over any repeated districts */
collapse (sum) cases_total death_total, by(date lgd_state_id lgd_district_id lgd_state_name lgd_district_name)
sort lgd_state_name lgd_district_name date

/* label and clean up */
label var date "case date"
// label var _m_lgd_districts "merge from raw case data to LGD districts"

/* resave the raw data */
compress
save $covidpub/covid/raw/covid_case_data_raw, replace

/* ensure data is square with each district and day */
use $covidpub/covid/raw/covid_case_data_raw, clear

/* make it square */
egen dgroup = group(lgd_state_name lgd_district_name)
fillin date dgroup 

/* set as time series with dgroup */
sort dgroup date
by dgroup: egen day_number = seq()

/* fill in state, district, lgd names within dgroup 
   to install xfill: net install xfill */
xfill lgd_state_name lgd_district_name lgd_state_id lgd_district_id, i(dgroup)

/* create cumulative sums of deaths and infections */
sort dgroup day_number

/* only save the cumulative counts */
drop dgroup _fillin day_number

/* rename variables to match standard names we are using */
ren cases_total total_cases
ren death_total total_deaths

/* order and save */
order lgd_state_id lgd_district_id date lgd_state_name lgd_district_name date total_cases total_deaths
compress
save $covidpub/covid/covid_infected_deaths, replace
export delimited using $covidpub/covid/csv/covid_infected_deaths.csv, replace

/* save PC11-identified version --> need to adjust this 06/05/2020 */
drop lgd_state_name lgd_district_name

/* for now this doesn't work becuase of the hierarchical matching issue (git issue #20 in tools) */
// convert_ids, from_ids(lgd_state_id lgd_district_id) to_ids(pc11_state_id pc11_district_id) long(date) key($keys/lgd_pc11_district_key_weights.dta) weight_var(lgd_pc11_wt_pop) labels metadata_urls(https://docs.google.com/spreadsheets/d/e/2PACX-1vTKTuciRsUd6pk5kWhlMyhF85Iv5x04b0njSrWzCkaN5IeEZpBwwvmSdw-mUJOp215jBgv2NPMeTHXK/pub?gid=0&single=true&output=csv)

/* run customized version of convert_ids to deal with the hierarchical matching issue */
local from_ids lgd_state_id lgd_district_id
local to_ids pc11_state_id pc11_district_id
local long date
local key $keys/lgd_pc11_district_key_weights.dta
local weight_var lgd_pc11_wt_pop
local metadata_urls "https://docs.google.com/spreadsheets/d/e/2PACX-1vTKTuciRsUd6pk5kWhlMyhF85Iv5x04b0njSrWzCkaN5IeEZpBwwvmSdw-mUJOp215jBgv2NPMeTHXK/pub?gid=0&single=true&output=csv"

/* pull in aggregation specification */
shell wget --no-check-certificate --output-document=$tmp/metadata_scrape.csv '`metadata_urls''
qui aggmethod_globals_from_csv $tmp/metadata_scrape.csv, labels

/* set variable list */
unab variables : _all

/* remove identifiers from the list */
local variables : list variables - from_ids
local variables : list variables - long

/* save mean values for each variable into locals for validation */
foreach var in `variables' {
  qui sum `var'
  local `var'_o = `r(mean)'
}

/* joinby state and district */
qui joinby `from_ids' using `key', unmatched(master)
drop _merge

/* merge in pc11 state id's */
merge m:1 lgd_state_id using $keys/lgd_pc11_state_key, keepusing(pc11_state_id) update
drop if _merge == 2
drop _merge

/* fill in remaining missing i's as not reported */
replace pc11_district_id = "999" if mi(pc11_district_id)
replace pc11_state_id = "99" if mi(pc11_state_id)

/* initialize a collapse string for instances where pc11 dists are aggregated to LGD (or vice versa) */
local collapse_string

/* conduct the weighting for all variables, using externally-defined globals. loop over calculated vars */
foreach var in `variables' {
  /* extract aggregation method into its own local */
  local clean_method = lower("${`var'_}")
  /* run the sum command - we know these are all sum, otherwise we would need to check
     and run functions as is done in convert_ids in tools.do */
  local collapse_string `collapse_string' (`clean_method') `var'
}

/* fill the weighted variable with 1 if missing */
replace `weight_var' = 1 if mi(`weight_var')

/* collapse to specified IDs. use iweights; aweights normalize
   group weights to sum to Ni, which we don't want */
collapse_save_labels
collapse `collapse_string' [iw = `weight_var'], by(`to_ids' `long')
collapse_apply_labels

/* check old and new values */
foreach var in `variables' {
  qui sum `var'
  local newmean = `r(mean)'
  if !inrange(`newmean', ``var'_o' * .8, ``var'_o' * 1.2) disp "WARNING: `var' has changed more than 20% from original value (``var'_o' -> `newmean')"
}
  
order pc11*, first
save $covidpub/covid/pc11/covid_infected_deaths_pc11, replace
export delimited using $covidpub/covid/csv/covid_infected_deaths_pc11.csv, replace
