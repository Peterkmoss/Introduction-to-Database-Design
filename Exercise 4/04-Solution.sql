/*
Schema:
accountrecords(rid, aid, rdate, rtype, ramount, rbalance)
accounts(aid, pid, adate, abalance, aover)
bills(bid, pid, bduedate, bamount, bispaid)
people(pid, pname, pgender, pheight)

*/

-- Setup --
    drop function if exists BanChanges() cascade;

    CREATE function BanChanges()
    returns trigger
    as $$
    begin
        RAISE exception 'BanChanges: Cannot change entries!';
    end; $$
    LANGUAGE plpgsql;
-- End Setup --

-- Ex 1
/*
    DROP VIEW IF EXISTS AllAccountRecords;

    create view AllAccountRecords
    as
    select a.aid, a.pid, a.adate, a.abalance, a.aover, 
        ar.rid, ar.rdate, ar.rtype, ar.ramount, ar.rbalance
    from accounts a
        left join accountrecords ar on a.aid = ar.aid;
*/

-- Ex 2
/*
    DROP TRIGGER IF EXISTS CheckBills on bills;
    DROP FUNCTION IF EXISTS CheckBills();

    CREATE TRIGGER BanUpdate
    before update or delete
    on Bills
    for each row execute procedure BanChanges();

    CREATE FUNCTION CheckBills()
    RETURNS TRIGGER
    AS $$ BEGIN
        IF (NEW.bamount < 0) THEN
            RAISE EXCEPTION 'CheckBills: Amount must be positive!';
        END IF;
        IF (NEW.bduedate <= CURRENT_DATE) THEN
            RAISE EXCEPTION 'CheckBills: Duedate must be tomorrow or later!';
        END IF;
        RETURN NEW;
    END; $$ LANGUAGE plpgsql;

    CREATE TRIGGER CheckBills
    BEFORE INSERT
    ON bills
    FOR EACH ROW EXECUTE PROCEDURE CheckBills();
*/

-- Ex 3
/*
    DROP TRIGGER IF EXISTS NewRecord on AccountRecords;
    DROP FUNCTION IF EXISTS NewRecord();

    CREATE TRIGGER BanUpdate
    before update or delete
    on AccountRecords
    for each row execute procedure BanChanges();

    CREATE FUNCTION NewRecord()
    RETURNS TRIGGER
    AS $$ 
    DECLARE
        newBalance FLOAT;
    BEGIN
        if (new.ramount < 0 and -new.ramount >= (select abalance + aover from accounts a where a.aid = new.aid)) THEN
            raise exception 'Ex3: Not enough money!';
        else
            select (a.abalance + new.rAmount) into newBalance
            from accounts a 
            where a.aid = new.aid;

            update accounts a
            set abalance = newBalance, adate = CURRENT_DATE
            where a.aid = new.aid;

            new.rdate = CURRENT_DATE;
            new.rbalance = newBalance;
        end if;
        return new;
    END; $$ 
    LANGUAGE plpgsql;

    CREATE TRIGGER NewRecord
    BEFORE INSERT
    ON AccountRecords
    for each row execute PROCEDURE NewRecord();
*/

-- Ex 4
/*
    drop function if exists Transfer(iToAID int, iFromAID int, iAmount int);

    create function Transfer(iToAID int, iFromAID int, iAmount int)
    returns void
    as 
    $$
    begin
        insert into accountrecords(aid, rtype, ramount) values (iFromAID, 'T', -iAmount);
        insert into accountrecords(aid, rtype, ramount) values (iToAID, 'T', iAmount);
        return;
    end; $$ LANGUAGE plpgsql;
*/

-- Ex 5
/*
    drop view if exists DebtorStatus;

    create view DebtorStatus
    as
    select p.pid, pName, sum(abalance) as totalbalance, sum(aover) as totaloverdraft
    from people p
        join accounts a on a.pid = p.pid
    group by p.pid
    having sum(abalance) < 0;
*/

-- Ex 6
/*
    drop trigger if exists NewPerson on people;
    drop function if exists NewAccount();

    create function NewAccount()
    returns trigger
    as $$
    begin
        insert into accounts(pid, adate, abalance, aover) 
        values (new.pid, CURRENT_DATE, 0, 10000);
        return new;
    end; 
    $$ language plpgsql;

    create trigger NewPerson
    after insert
    on people
    for each row execute procedure NewAccount();
*/

-- Ex 7
/*
    drop function if exists InsertPerson(iName varchar, iGender varchar, iHeight float, iAmount int);

    create function InsertPerson(iName varchar, iGender varchar, iHeight float, iAmount int)
    returns void
    as $$
    declare
        account int;
    begin
        insert into people(pName, pGender, pHeight) values (iName, iGender, iHeight);

        select aid into account
        from accounts
        where (select max(pid) from people) = pid;

        insert into accountrecords(aid, rtype, ramount) values (account, 'T', iAmount);
        return;
    end; $$ language plpgsql;
*/

-- Ex 8
/*
    drop function if exists PayOneBill(ibid int);

    create function PayOneBill(ibid int)
    returns void
    as $$
    declare
        amount int;
        account int;
    begin
        if (select bispaid from bills where bid = ibid) = TRUE then
            raise exception 'PayOneBill: Bill is already paid!';
        end if;

        if (select bid from bills where bid = ibid) is null then
            raise exception 'PayOneBill: Bill does not exist!';
        end if;

        if (select count(a.aid) from bills b join accounts a on a.pid = b.pid where bid = ibid) = 0 then
            raise exception 'PayOneBill: Account does not exist!';
        end if;

        select bamount into amount
        from bills
        where bid = ibid;

        select aid into account
        from accounts a
            join bills b on a.pid = b.pid
        where bid = ibid
        order by abalance;

        insert into accountrecords(aid, rtype, ramount) values (account, 'B', -amount);

        update bills
        set bispaid = TRUE
        where bid = ibid;

        return;
    end; $$ language plpgsql;
*/

-- Ex 9
/*
    drop function if exists LoanMoney(iaid int, iamount int, iduedate date);

    create function LoanMoney(iaid int, iamount int, iduedate date)
    returns void
    as $$
    declare
        person int;
    begin
        if iamount <= 0 then
            raise exception 'LoanMoney: Amount must be positive!';
        end if;

        if iduedate <= CURRENT_DATE then
            raise exception 'LoanMoney: Due date must be in the future!';
        end if;

        insert into accountrecords(aid, rtype, ramount) values (iaid, 'L', iamount);

        select pid into person
        from accounts
        where aid = iaid;

        insert into bills(pid, bduedate, bamount, bispaid) values (person, iduedate, iamount, 'F');
        return;
    end; $$
    language plpgsql;
*/

-- Ex 10
/*
    drop view if exists FinancialStatus;
    drop view if exists TotalBalance;
    drop view if exists CountBills;

    create view TotalBalance
    as 
    select pid, sum(abalance) as balance
    from accounts
    group by pid;

    create view CountBills
    as
    select pid, count(bid) as unpaid
    from bills
    where bispaid = FALSE
    group by pid;

    create view FinancialStatus
    as
    select distinct a.pid, pname, balance, case
                                            when unpaid > 0 then unpaid
                                            else '0' end as "unpaid"
    from accounts a
        join people p on p.pid = a.pid
        join TotalBalance tb on tb.pid = a.pid
        left join CountBills cb on cb.pid = a.pid;
*/

-- TESTS --
--1----------------------------------------------------------------------
/*
    select '1. View AllAccountRecords' as now_testing;

    select 'This should find two accounts, 21 and 85, both of which are OK' as result;

    select PID, AID, sum(rAmount), max(aBalance), case sum(rAmount) = max(aBalance) when true then 'OK' else 'Not OK' end
    from AllAccountRecords 
    where PID = 50
    group by PID, AID;

    select 'This should find 21 accounts with no records (check on outer join)' as result;

    select count(*)
    from AllAccountRecords 
    where rAmount is null;
*/

--2----------------------------------------------------------------------
/*
    select '2. Trigger on Bills' as now_checking;

    begin transaction;

    select 'This should give error on date' as result;

    insert into Bills ( PID, bDueDate, bAmount, bIsPaid )
    values ( 5, CURRENT_DATE, 10000, FALSE );

    rollback; 

    begin transaction;

    select 'This should give error on amount' as result;

    insert into Bills ( PID, bDueDate, bAmount, bIsPaid )
    values ( 5, CURRENT_DATE + 30, -10000, FALSE );

    rollback; 

    begin transaction;

    select 'This should give error as updates are forbidden' as result;

    update Bills
    set bAmount = 5000
    where BID = 3;

    rollback; 

    begin transaction;

    select 'This should give error as deletes are forbidden' as result;

    delete 
    from Bills
    where BID = 3;

    rollback; 

    begin transaction;

    select 'This insert should work' as result;

    insert into Bills ( PID, bDueDate, bAmount, bIsPaid )
    values ( 5, CURRENT_DATE + 30, 10000, FALSE );

    select 'This should show one account' as result;

    select count(*)
    from Bills
    where PID = 5
    and bDueDate > CURRENT_DATE;

    rollback;

    select 'This should show no account' as result;

    select count(*)
    from Bills
    where PID = 5
    and bDueDate > CURRENT_DATE;

*/

--3---------------------------------------------------------------------
/*
    select '3. Trigger on AccountRecords' as now_testing;

    select 'Creating a function to find bogus accounts' as message;

    CREATE OR REPLACE FUNCTION FindBogusAccounts() 
    RETURNS TABLE (AID INTEGER, PID INTEGER, aDate DATE, aBalance INTEGER, aOver INTEGER)
    AS 
    $$
        SELECT *
        FROM Accounts A
        WHERE (
            A.aBalance <> 0 OR
            EXISTS (
                SELECT * 
                FROM AccountRecords R1 
                WHERE R1.AID = A.AID))
        AND NOT EXISTS(
            SELECT *
            FROM AccountRecords R
            WHERE A.AID = R.AID 
            AND A.aDate = R.rdate
            AND A.aBalance = R.rBalance
            AND R.RID = (
                SELECT MAX(R2.RID)
                FROM AccountRecords R2
                WHERE R2.AID = A.AID)) 
    $$ 
    LANGUAGE sql;

    select 'There should be 0 bogus accounts' as result;

    select count(*) as bogus
    from FindBogusAccounts()
    where AID <> 90;

    begin transaction;

    select 'This should give error on amount' as result;

    insert into AccountRecords ( AID, rType, rAmount )
    values ( 5, 'T', -100000 );

    rollback; 

    select 'There should be 0 bogus accounts' as result;

    select count(*) as bogus
    from FindBogusAccounts()
    where AID <> 90;

    begin transaction;

    select 'This should give error as updates are forbidden' as result;

    update AccountRecords
    set rAmount = 5000
    where RID = 3;

    rollback; 

    begin transaction;

    select 'This should give error as deletes are forbidden' as result;

    delete 
    from AccountRecords
    where RID = 3;

    rollback; 

    begin transaction;

    select 'This deposit should work fine' as result;

    insert into AccountRecords ( AID, rType, rAmount )
    values ( 5, 'T', 100000 );

    select 'BONUS: This should still return 0' as result;

    select count(*) as bogus
    from FindBogusAccounts()
    where AID <> 90;

    select 'Just in case we do not get an empty result, then check it was account 5' as result;

    select *
    from FindBogusAccounts() A left outer join AccountRecords R on A.AID = R.AID
    where A.AID <> 90;

    rollback; 
*/

--4---------------------------------------------------------------------
/*
    select '4. Function Transfer' as now_testing;

    begin transaction;

    select 'Transfer from 8 to 2 should not work (insufficient funds)' as result;

    select Transfer ( 2, 8, 1 );

    rollback; 

    begin transaction;

    select 'BONUS: Transfer from 2 to 8 of negative amount should NOT work' as result;

    select Transfer ( 2, 8, -1 );

    rollback; 

    begin transaction;

    select 'Transfer from 8 to 2 of 0 amount should work' as result;

    select Transfer ( 8, 2, 0 );

    select 'These are the most recent entries' as result;

    select * 
    from AccountRecords
    where RID >= -1 + (select max(RID) from AccountRecords);

    rollback; 

    begin transaction;

    select 'Transfer from 2 to 200000 should NOT work' as result;

    select Transfer ( 2, 200000, 1 );

    rollback; 
*/

--5---------------------------------------------------------------------
/*
    select '5. View DebtorStatus' as now_checking;

    select 'Should return 28 debtors' as result;

    select count(*)
    from DebtorStatus;

    select 'Two women owe more than 10K' as result;

    select *
    from DebtorStatus
    where totalbalance < -10000;
*/

--6---------------------------------------------------------------------
/*
    select '6. Trigger on Persons' as now_testing;

    begin transaction;

    select 'This insert should work' as result;

    insert into People (pName, pGender, pHeight)  
    values ('Gummi', 'M', 1.74);

    select 'This should return Gummi and one account with overdraft of 10000' as result;

    select *
    from People P
        join Accounts A on A.PID = P.PID 
    where A.AID = (select max (A1.AID) from Accounts A1);

    select 'This should return 0 account records for the new person' as result;

    select count(*) as count
    from AccountRecords R
    where R.AID = (select max (A1.AID) from Accounts A1);

    rollback; 
*/

--7---------------------------------------------------------------------
/*
    select '7. Function InsertPerson' as now_testing;

    begin transaction;

    select 'This insert should work' as result;

    select InsertPerson ('Gummi', 'M', 1.74, 21000);

    select 'This should return Gummi and one account with balance of 21000' as result;

    select *
    from People P
        join Accounts A on A.PID = P.PID 
    where A.AID = (select max (A1.AID) from Accounts A1);

    select 'This should return 1 account record for Gummi' as result;

    select *
    from AccountRecords R
    where R.AID = (select max (A1.AID) from Accounts A1);

    rollback; 
*/

--8---------------------------------------------------------------------
/*
    select '8. Function PayOneBill' as now_testing;

    begin transaction;

    select 'Payment of bill 12 should work (over = 22000)' as result;

    select PayOneBill ( 12 );

    select 'Bill 12 should now be paid' as result;

    select * 
    from Bills
    where BID = 12;

    select 'Amount of bill 12 was 207, so account balance should be -207' as result;

    select *
    from AccountRecords 
    where RID = (select max(RID) from AccountRecords);

    rollback; 

    begin transaction;

    select 'Making a person with two identically valued accounts' as message;

    update Accounts
    set aOver = 63000
    where AID = 5;

    select 'Note the lastval' as result;

    select lastval();

    select 'Payment of bill 29 should work' as result;

    select PayOneBill ( 29 );

    select 'Compare with the new lastval -- should be one higher' as result;

    select lastval();

    select 'Check the accounts of PID 10 - one should be 0, the other -8405' as result;

    select *
    from Accounts
    where PID = 10;

    rollback; 

    begin transaction;

    select 'Payment of bill 108 should not work (already paid)' as result;

    select PayOneBill (108);

    rollback; 

    begin transaction;

    select 'Payment of bill 20000 should not work (does not exist)' as result;

    select PayOneBill (20000);

    rollback; 

    begin transaction;

    select 'Payment of bill 3 should not work (no account)' as result;

    select PayOneBill (3);

    rollback; 

    begin transaction;

    select 'Payment of bill 107 should not work (insufficient funds)' as result;

    select PayOneBill (107);

    rollback; 
*/

--9---------------------------------------------------------------------
/*
    select '9. Function LoanMoney' as now_testing;

    begin transaction;

    select 'Loaning a negative amount should not work' as result;

    select LoanMoney ( 6, -1, CURRENT_DATE );

    rollback; 

    begin transaction;

    select 'Loaning with due date today should not work' as result;

    select LoanMoney ( 6, 1, CURRENT_DATE );

    rollback; 

    begin transaction;

    select 'This loan should work' as result;

    select LoanMoney ( 6, 10000, CURRENT_DATE+100 );

    select 'The account should contain 10000' as result;

    select * from Accounts where PID = 100;

    select 'The most recent bill should be for 10000 for PID 100' as result;

    select * from Bills 
    where BID = (select max(BID) from Bills);

    rollback; 
*/

--10---------------------------------------------------------------------
/*
    select '10. View FinancialStatus' as now_checking;

    select 'This should return 79 people' as result;

    select count(*)
    from FinancialStatus;

    select 'Return person 78 with 18073 as balance, 0 as unpaid' as result;

    select *
    from FinancialStatus
    where PID = 78;
*/