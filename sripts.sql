/**can be used for cleanup after tests */
begin try drop table dbo.Elevator end try begin catch end catch
begin try drop table dbo.Active_Queue end try begin catch select error_message() end catch
begin try drop table dbo.Archive end try begin catch end catch
begin try drop procedure dbo.SP_Log_Request end try begin catch end catch
begin try drop procedure dbo.SP_Stop end try begin catch end catch
begin try drop procedure dbo.SP_GO end try begin catch end catch
begin try drop procedure dbo.SP_Maintanance_Report end try begin catch end catch
go

/*Creating the tables and iserting the values*/
create table dbo.Elevator
(
	ID int Identity(1,1) Primary key,
	Model varchar(30),
	Max_Weight smallint,
	Current_State varchar(30),
	Maintanance_Floors int,
	Maintanance_Load int
)
go 

insert into dbo.Elevator 
values	('Standard', 1500, 'Idle', 150000, 4500),
		('Extra Load', 2500, 'Idle', 200000, 7500),
		('Standard', 1500, 'Idle', 150000, 4500)
go 

create table dbo.Active_Queue
(
	ID int Identity(1,1) Primary key,
	Elevator_ID int,
	Request_floor int, 
	Requested_floor int,
	Estimated_Direction varchar(10),
	Transported_Load smallint, 
	Is_External bit
)
go

create table dbo.Archive
(
	Request_ID int,
	Elevator_ID int,
	Traveled_Floors smallint,
	Delivered_Weight smallint 
)
go
/*Creating the tables and iserting the values*/

/*Crating the procedures that will excute the tasks*/
 

create procedure SP_Log_Request 
	@p_request_floor_id smallint,
	@p_direction varchar(10) = null, --(null for internal requests)
	@p_is_external bit = 1,
	@p_requested_floor int = null, --(null for external queries),
	@p_elevator_id smallint = 0 --( 0 for external queries)
	
as 
begin try 
	declare 
			@p_request_id int
	--get the optimal elevator
	if @p_is_external = 1
	begin 
	 --optimization of which elevator will be assigned with the request 
		select top 1 @p_elevator_id = Elevator_ID 
		from dbo.Active_Queue a
		where a.Requested_floor <= @p_request_floor_id and a.Estimated_Direction = @p_direction

		--get an idle elevator on second check (Idle state)
		if @p_elevator_id = 0
			select top 1 @p_elevator_id = ID
			from dbo.Elevator 
			where Current_State = 'Idle'

		if @p_elevator_id = 0
		--get the elevator with less traveling time
		begin 
			declare @table_sum table
			(
				Elevator_ID smallint,
				Total_floors int
			)

			insert into @table_sum
			select Elevator_ID, count(ID)
			from dbo.Active_Queue
			group by Elevator_ID

			select top 1 @p_elevator_id = Elevator_ID
			from @table_sum
			order by Total_floors
		end 
		--log the query 
		insert into dbo.Active_Queue (Elevator_ID, Request_floor, Requested_floor, Estimated_Direction, Transported_Load, Is_External)
		select top 1 @p_elevator_id, @p_request_floor_id, isnull(Requested_floor, 0), @p_direction, isnull(Transported_Load, 0), @p_is_external
		from dbo.Active_Queue a
			right outer join dbo.Elevator e on a.Elevator_ID = e.ID --if the elevator is idle
		where e.ID = @p_elevator_id
		order by a.ID desc

		set @p_request_id = @@identity

		--update if the chosen elevator is IDLE
		update e 
		set e.Current_State = a.Estimated_Direction
		from dbo.Elevator e
			inner join dbo.Active_Queue a on e.ID = a.Elevator_ID and a.ID = @p_request_id and e.Current_State = 'Idle'	
	end
	else 
	begin 
		
		insert into dbo.Active_Queue (Elevator_ID, Request_floor, Requested_floor, Estimated_Direction, Transported_Load, Is_External)
		select top 1 @p_elevator_id, @p_request_floor_id, @p_requested_floor, iif(isnull(Requested_floor, 0) - @p_request_floor_id > 0, 'Down', 'UP'),
					 isnull(Transported_Load, 0), @p_is_external
		from dbo.Active_Queue a
			right outer join dbo.Elevator e on a.Elevator_ID = e.ID --if the elevator is idle
		where e.ID = @p_elevator_id
		order by a.ID desc

		set @p_request_id = @@identity

		--update if the chosen elevator is IDLE
		update e 
		set e.Current_State = a.Estimated_Direction
		from dbo.Elevator e
			inner join dbo.Active_Queue a on e.ID = a.Elevator_ID and a.ID = @p_request_id and e.Current_State = 'Idle'
	end 

	select @p_elevator_id as Requested_Elevator
end try 
begin catch 
	print 'THE TECHNICIAN TEAM IS NOTIFIED FOR THE ERROR AND WILL REPOSND ASAP'
end catch 
go
/*****************************************************/
create procedure SP_Stop
	@p_request_id int
as 
begin try 

	declare @p_elevator_id int 

	select @p_elevator_id = Elevator_ID
	from dbo.Active_Queue
	where ID = @p_request_id
	--check if the elevator is full on external request handle
	if exists (select e.ID 
				from dbo.Elevator e 
						inner join dbo.Active_Queue a on e.ID = a.Elevator_ID and a.ID = @p_request_id
														and e.Max_Weight <= a.Transported_Load and a.Is_External = 1)
	begin 
		declare @p_request_floor smallint,
				@p_direction varchar(10),
				@p_requested_floor smallint 
				
		select @p_request_floor = Request_floor, @p_direction = Estimated_Direction
		from dbo.Active_Queue 
		where ID = @p_request_id

		delete from dbo.Active_Queue where ID = @p_request_id 

		exec SP_Log_Request 
			@p_request_floor_id = @p_requested_floor,
			@p_direction = @p_direction

		raiserror('', 16, 1)
	end 
	else 
	begin 
	 -- if the request is internal stop and archive
		if exists (select ID from dbo.Active_Queue where ID = @p_request_id and Is_External = 0)
			delete from dbo.Active_Queue
			output  DELETED.ID, DELETED.Elevator_ID, DELETED.Transported_Load, 
			(DELETED.Request_floor - DELETED.Requested_floor) * iif(DELETED.Request_floor - DELETED.Requested_floor < 0, -1, 1)
			into dbo.Archive (Request_ID, Elevator_ID, Delivered_Weight, Traveled_Floors) 
			where ID = @p_request_id

		if not exists (select ID  from dbo.Active_Queue where Elevator_ID = @p_elevator_id)
		--set the elevator to Idle
		update e
		set e.Current_State = 'Idle'
		from dbo.Elevator e
		where e.ID = @p_elevator_id
	end
	
end try 
begin catch 
	select 'YOUR REQUEST CAN`T BE FULFILLED DUE TO OVERLOAD AND WILL BE HANDLED BY THE MOST OPTIMAL ELEVATOR'
	print error_message()
end catch 
go
 /*****************************************************/
 create procedure SP_GO
	@p_request_id int,
	@p_current_weight int = 0,
	@p_input_weight int = 0,
	@p_output_weight int = 0
as 
begin try 
	--check for overload
	if exists (select e.ID 
				from dbo.Elevator e
					inner join dbo.Active_Queue a on a.Elevator_ID = e.ID and a.ID = @p_request_id
					where e.Max_Weight <= (@p_current_weight + @p_input_weight) - @p_output_weight) 
		raiserror('Elevator is overloaded', 16, 1)
	else 
	begin 
		declare @p_elevator_id smallint 

		select @p_elevator_id = Elevator_id 
		from dbo.Active_Queue
		where ID = @p_request_id

		update a  
		set Transported_Load = (@p_current_weight + @p_input_weight) - @p_output_weight
		from dbo.Active_Queue a 
		where a.ID >= @p_request_id and a.Elevator_ID = @p_elevator_id

		if  exists (select ID from dbo.Active_Queue where ID = @p_request_id and Is_External = 1)
		 -- if the request is external and archive
			delete from dbo.Active_Queue
			output  DELETED.ID, DELETED.Elevator_ID, DELETED.Transported_Load, 
			(DELETED.Request_floor - DELETED.Requested_floor) * iif(DELETED.Request_floor - DELETED.Requested_floor < 0, -1, 1)
			into dbo.Archive (Request_ID, Elevator_ID, Delivered_Weight, Traveled_Floors) 
			where ID = @p_request_id

		if not exists (select ID  from dbo.Active_Queue where Elevator_ID = @p_elevator_id)
			--set the elevator to Idle
			update e
			set e.Current_State = 'Idle'
			from dbo.Elevator e
			where e.ID = @p_elevator_id	
	 end
end try 
begin catch 
	print 'THE ELEVATOR IS OVERLOADED AND CAN`T PROCEED'
end catch 
go
/*****************************************************/
 create procedure SP_Maintanance_Report
   @p_elevator_id int = 0,
   @p_request_id int = 0
as 
begin try 
	declare @table_out table
	(
		current_traveled_floors int,
		current_delivered_weight int,
		is_for_maintenance varchar(100)
	)

	declare @p_max_weight int,
			@p_max_floors int 
	
	select @p_max_weight = Maintanance_Load, @p_max_floors = Maintanance_Floors 
	from dbo.Elevator
	where ID = @p_elevator_id

	if @p_request_id = 0
		insert into @table_out (current_traveled_floors, current_delivered_weight)
		select isnull(sum(Traveled_Floors),0), isnull(sum(Delivered_Weight),0)
		from dbo.Archive  
		where Elevator_ID = @p_elevator_id
	else 
		insert into @table_out (current_traveled_floors, current_delivered_weight)
		select isnull(Traveled_Floors,0), isnull(Delivered_Weight,0)
		from dbo.Archive  
		where Request_ID = @p_request_id

	if @p_request_id = 0 --check for maintananec if not called for certain request
		update @table_out 
		set is_for_maintenance = case when @p_max_floors <= current_traveled_floors then 'For Maintenance'
									  when @p_max_weight <= current_delivered_weight then 'For Maintenance'
									  else 'Elevator haven`t reached its maintenance limit'
									  end

	if @p_request_id = 0
		select * from @table_out
	else 
		select current_traveled_floors, current_delivered_weight from @table_out 
end try 
begin catch 
	print 'There is an error! Please run the report again'
	print error_message()  
end catch 
go

/*Crating the procedures that will excute the tasks*/


