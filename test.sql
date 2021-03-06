/*put some load on the elevators*/

exec SP_Log_Request 
	@p_request_floor_id = 15,
	@p_direction = 'UP',
	@p_is_external =1
go
exec SP_Log_Request 
	@p_request_floor_id = 25,
	@p_requested_floor = 50,
	@p_is_external =0,
	@p_elevator_id = 2
go
--simulate and overload on request 2
exec SP_GO
 @p_request_id = 2,
 @p_current_weight = 0,
 @p_input_weight = 2501,
 @p_output_weight = 0
go
--execute GO normaly
exec SP_GO
 @p_request_id = 2,
 @p_current_weight = 0,
 @p_input_weight = 2499,
 @p_output_weight = 0

--stop on request 2
exec SP_Stop
@p_request_id = 2

--stop on request 1
exec SP_Stop
@p_request_id = 1
--go on request 1
exec SP_GO 
@p_request_id = 1,
@p_current_weight = 100,
@p_input_weight = 200,
@p_output_weight = 100

--simulate refusing a stop
exec SP_Log_Request 
	@p_request_floor_id = 15,
	@p_direction = 'UP',
	@p_is_external =1

select * from dbo.Active_Queue --get the id of the request
update a 
set a.Transported_Load = e.Max_Weight
from dbo.Active_Queue a
	inner join dbo.Elevator e
	on a.Elevator_ID = e.ID and a.ID = /*request_id*/

exec SP_Stop 
@p_request_id = --request id that is prepared


--check the mainatance report of elevator 2
exec SP_Maintanance_Report
@p_elevator_id = 2