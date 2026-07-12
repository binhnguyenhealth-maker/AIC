# Frozen Chicago IUCR mapping

This file documents the exact Chicago Police Department IUCR codes admitted to the AIC Chicago beta pipeline. The machine-readable source of truth is [`iucr_mapping.json`](./iucr_mapping.json).

- Official source: City of Chicago dataset [`c7ck-438e`](https://data.cityofchicago.org/d/c7ck-438e)
- Frozen at: `2026-07-11T01:40:00Z`
- Official source update epoch recorded at freeze: `1780434514`
- Frozen codes: `86`; each code appears exactly once
- Inclusion is IUCR-first. `primary_type` is a required consistency check, not the selector.
- On a refreshed source build, a newly added, removed, reclassified, or duplicated selected-category code fails until this mapping receives explicit review.
- Inactive historical codes remain frozen so old/reclassified source records cannot silently change category. The manifest records which frozen codes actually occurred in the selected period.

| IUCR | AIC category | Official primary | Official secondary | Index | Active |
|---|---|---|---|---|---|
| `041A` | `assault_battery` | BATTERY | AGGRAVATED - HANDGUN | I | yes |
| `041B` | `assault_battery` | BATTERY | AGGRAVATED - OTHER FIREARM | I | yes |
| `0420` | `assault_battery` | BATTERY | AGGRAVATED - KNIFE / CUTTING INSTRUMENT | I | yes |
| `0430` | `assault_battery` | BATTERY | AGGRAVATED - OTHER DANGEROUS WEAPON | I | yes |
| `0440` | `assault_battery` | BATTERY | AGGRAVATED - HANDS, FISTS, FEET, NO / MINOR INJURY | N | yes |
| `0450` | `assault_battery` | BATTERY | AGGRAVATED POLICE OFFICER - HANDGUN | I | yes |
| `0451` | `assault_battery` | BATTERY | AGGRAVATED POLICE OFFICER - OTHER FIREARM | I | yes |
| `0452` | `assault_battery` | BATTERY | AGGRAVATED POLICE OFFICER - KNIFE / CUTTING INSTRUMENT | I | yes |
| `0453` | `assault_battery` | BATTERY | AGGRAVATED POLICE OFFICER - OTHER DANGEROUS WEAPON | I | yes |
| `0454` | `assault_battery` | BATTERY | AGGRAVATED P.O. - HANDS, FISTS, FEET, NO / MINOR INJURY | N | yes |
| `0460` | `assault_battery` | BATTERY | SIMPLE | N | yes |
| `0461` | `assault_battery` | BATTERY | AGGRAVATED P.O. - HANDS, FISTS, FEET, SERIOUS INJURY | I | yes |
| `0462` | `assault_battery` | BATTERY | AGG. PROTECTED EMPLOYEE - HANDS, FISTS, FEET, SERIOUS INJURY | I | yes |
| `0475` | `assault_battery` | BATTERY | OF AN UNBORN CHILD | N | yes |
| `0479` | `assault_battery` | BATTERY | AGGRAVATED - HANDS, FISTS, FEET, SERIOUS INJURY | I | yes |
| `0480` | `assault_battery` | BATTERY | AGGRAVATED PROTECTED EMPLOYEE - HANDGUN | I | yes |
| `0481` | `assault_battery` | BATTERY | AGGRAVATED PROTECTED EMPLOYEE - OTHER FIREARM | I | yes |
| `0482` | `assault_battery` | BATTERY | AGGRAVATED PROTECTED EMPLOYEE - KNIFE / CUTTING INSTRUMENT | I | yes |
| `0483` | `assault_battery` | BATTERY | AGGRAVATED PROTECTED EMPLOYEE - OTHER DANGEROUS WEAPON | I | yes |
| `0484` | `assault_battery` | BATTERY | PROTECTED EMPLOYEE - HANDS, FISTS, FEET, NO / MINOR INJURY | N | yes |
| `0485` | `assault_battery` | BATTERY | AGGRAVATED OF A CHILD | I | yes |
| `0486` | `assault_battery` | BATTERY | DOMESTIC BATTERY SIMPLE | N | yes |
| `0487` | `assault_battery` | BATTERY | AGGRAVATED OF AN UNBORN CHILD | I | yes |
| `0488` | `assault_battery` | BATTERY | AGGRAVATED DOMESTIC BATTERY - HANDGUN | I | yes |
| `0489` | `assault_battery` | BATTERY | AGGRAVATED DOMESTIC BATTERY - OTHER FIREARM | I | yes |
| `0495` | `assault_battery` | BATTERY | AGGRAVATED OF A SENIOR CITIZEN | I | yes |
| `0496` | `assault_battery` | BATTERY | AGGRAVATED DOMESTIC BATTERY - KNIFE / CUTTING INSTRUMENT | I | yes |
| `0497` | `assault_battery` | BATTERY | AGGRAVATED DOMESTIC BATTERY - OTHER DANGEROUS WEAPON | I | yes |
| `0498` | `assault_battery` | BATTERY | AGG. DOMESTIC BATTERY - HANDS, FISTS, FEET, SERIOUS INJURY | I | yes |
| `0499` | `assault_battery` | BATTERY | AGGRAVATED DOMESTIC BATTERY | I | no |
| `051A` | `assault_battery` | ASSAULT | AGGRAVATED - HANDGUN | I | yes |
| `051B` | `assault_battery` | ASSAULT | AGGRAVATED - OTHER FIREARM | I | yes |
| `0520` | `assault_battery` | ASSAULT | AGGRAVATED - KNIFE / CUTTING INSTRUMENT | I | yes |
| `0530` | `assault_battery` | ASSAULT | AGGRAVATED - OTHER DANGEROUS WEAPON | I | yes |
| `0545` | `assault_battery` | ASSAULT | PROTECTED EMPLOYEE - HANDS, FISTS, FEET, NO / MINOR INJURY | N | yes |
| `0550` | `assault_battery` | ASSAULT | AGGRAVATED POLICE OFFICER - HANDGUN | I | yes |
| `0551` | `assault_battery` | ASSAULT | AGGRAVATED POLICE OFFICER - OTHER FIREARM | I | yes |
| `0552` | `assault_battery` | ASSAULT | AGGRAVATED POLICE OFFICER - KNIFE / CUTTING INSTRUMENT | I | yes |
| `0553` | `assault_battery` | ASSAULT | AGGRAVATED POLICE OFFICER - OTHER DANGEROUS WEAPON | I | yes |
| `0554` | `assault_battery` | ASSAULT | AGGRAVATED POLICE OFFICER - HANDS, FISTS, FEET, NO INJURY | N | yes |
| `0555` | `assault_battery` | ASSAULT | AGGRAVATED PROTECTED EMPLOYEE - HANDGUN | I | yes |
| `0556` | `assault_battery` | ASSAULT | AGGRAVATED PROTECTED EMPLOYEE - OTHER FIREARM | I | yes |
| `0557` | `assault_battery` | ASSAULT | AGGRAVATED PROTECTED EMPLOYEE - KNIFE / CUTTING INSTRUMENT | I | yes |
| `0558` | `assault_battery` | ASSAULT | AGGRAVATED PROTECTED EMPLOYEE - OTHER DANGEROUS WEAPON | I | yes |
| `0560` | `assault_battery` | ASSAULT | SIMPLE | N | yes |
| `0910` | `motor_vehicle_theft` | MOTOR VEHICLE THEFT | AUTOMOBILE | I | yes |
| `0915` | `motor_vehicle_theft` | MOTOR VEHICLE THEFT | TRUCK, BUS, MOTOR HOME | I | yes |
| `0917` | `motor_vehicle_theft` | MOTOR VEHICLE THEFT | CYCLE, SCOOTER, BIKE WITH VIN | I | yes |
| `0918` | `motor_vehicle_theft` | MOTOR VEHICLE THEFT | CYCLE, SCOOTER, BIKE NO VIN | I | yes |
| `0920` | `motor_vehicle_theft` | MOTOR VEHICLE THEFT | ATTEMPT - AUTOMOBILE | I | yes |
| `0925` | `motor_vehicle_theft` | MOTOR VEHICLE THEFT | ATTEMPT - TRUCK, BUS, MOTOR HOME | I | yes |
| `0927` | `motor_vehicle_theft` | MOTOR VEHICLE THEFT | ATTEMPT - CYCLE, SCOOTER, BIKE WITH VIN | I | yes |
| `0928` | `motor_vehicle_theft` | MOTOR VEHICLE THEFT | ATTEMPT - CYCLE, SCOOTER, BIKE NO VIN | I | yes |
| `0930` | `motor_vehicle_theft` | MOTOR VEHICLE THEFT | THEFT / RECOVERY - AUTOMOBILE | I | yes |
| `0935` | `motor_vehicle_theft` | MOTOR VEHICLE THEFT | THEFT / RECOVERY - TRUCK, BUS, MOBILE HOME | I | yes |
| `0937` | `motor_vehicle_theft` | MOTOR VEHICLE THEFT | THEFT / RECOVERY - CYCLE, SCOOTER, BIKE WITH VIN | I | yes |
| `0938` | `motor_vehicle_theft` | MOTOR VEHICLE THEFT | THEFT / RECOVERY - CYCLE, SCOOTER, BIKE NO VIN | I | yes |
| `0312` | `robbery` | ROBBERY | ARMED - KNIFE / CUTTING INSTRUMENT | I | yes |
| `0313` | `robbery` | ROBBERY | ARMED - OTHER DANGEROUS WEAPON | I | yes |
| `031A` | `robbery` | ROBBERY | ARMED - HANDGUN | I | yes |
| `031B` | `robbery` | ROBBERY | ARMED - OTHER FIREARM | I | yes |
| `0320` | `robbery` | ROBBERY | STRONG ARM - NO WEAPON | I | yes |
| `0325` | `robbery` | ROBBERY | VEHICULAR HIJACKING | I | yes |
| `0326` | `robbery` | ROBBERY | AGGRAVATED VEHICULAR HIJACKING | I | yes |
| `0330` | `robbery` | ROBBERY | AGGRAVATED | I | yes |
| `0331` | `robbery` | ROBBERY | ATTEMPT AGGRAVATED | I | yes |
| `0334` | `robbery` | ROBBERY | ATTEMPT ARMED - KNIFE / CUTTING INSTRUMENT | I | yes |
| `0337` | `robbery` | ROBBERY | ATTEMPT ARMED - OTHER DANGEROUS WEAPON | I | yes |
| `033A` | `robbery` | ROBBERY | ATTEMPT ARMED - HANDGUN | I | yes |
| `033B` | `robbery` | ROBBERY | ATTEMPT ARMED - OTHER FIREARM | I | yes |
| `0340` | `robbery` | ROBBERY | ATTEMPT STRONG ARM - NO WEAPON | I | yes |
| `0710` | `theft` | THEFT | THEFT FROM MOTOR VEHICLE | I | yes |
| `0810` | `theft` | THEFT | OVER $500 | I | yes |
| `0820` | `theft` | THEFT | $500 AND UNDER | I | yes |
| `0830` | `theft` | THEFT | THEFT RETAIL | I | no |
| `0840` | `theft` | THEFT | FINANCIAL IDENTITY THEFT: OVER $300 | I | no |
| `0841` | `theft` | THEFT | FINANCIAL IDENTITY THEFT: $300 & UNDER | I | no |
| `0842` | `theft` | THEFT | AGGRAVATED: FINANCIAL IDENTITY THEFT | I | no |
| `0843` | `theft` | THEFT | ATTEMPT FINANCIAL IDENTITY THEFT | I | no |
| `0850` | `theft` | THEFT | ATTEMPT THEFT | I | yes |
| `0860` | `theft` | THEFT | RETAIL THEFT | I | yes |
| `0865` | `theft` | THEFT | DELIVERY CONTAINER THEFT | I | yes |
| `0870` | `theft` | THEFT | POCKET-PICKING | I | yes |
| `0880` | `theft` | THEFT | PURSE-SNATCHING | I | yes |
| `0890` | `theft` | THEFT | FROM BUILDING | I | yes |
| `0895` | `theft` | THEFT | FROM COIN-OPERATED MACHINE OR DEVICE | I | yes |

## Build invariants

1. The frozen file has unique four-character IUCR keys and exactly one AIC category per key.
2. Every frozen key must still exist in the retrieved official IUCR source with identical primary description, secondary description, index flag, and active flag.
3. Every official IUCR row whose primary description is one of the five admitted source types must appear in the frozen file; a new official code therefore fails closed.
4. Every included incident must have a frozen IUCR code and a `primary_type` equal to that code’s official primary description.
5. Only non-overlapping 250 m cells with four independently nearest-five-quantized category bands are shipped. IUCR codes and incident-level rows remain in the ignored build cache and never enter the application pack.
