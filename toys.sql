/* ============================
    Data import
    ==================================*/
create table sales1 (Sale_ID int ,
 date varchar(20)   ,
 Store_ID int , 
 Product_ID int ,
 Unit int )  ;

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/sales1.csv'
INTO TABLE sales1
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 ROWS; 

rename table sales1 to sales ;

/* ============================
    data cleaning and STRUCTURING
    ==================================*/
-- =============================================
-- PART 1: PRIMARY KEY ADDITION
-- =============================================
	-- 1.1 check NULLs
    
select store_id from stores 
where store_id is null ;

select product_id from products 
where product_id is null ; 

        -- 1.2 Identify duplicates
select Store_ID , count(*) from stores 
group by store_id 
having count(*) > 1 ; 

select Product_ID , count(*) from products
group by product_id 
having count(*) > 1; 

select sale_ID , count(*) from sales
group by Sale_ID
having count(*) > 1; 

  -- 1.3 Add Primary Keys 
alter table products 
add primary key(product_id ) ;

alter table stores 
add primary key (store_id ); 

alter table sales 
add primary key (sale_ID) ; 

-- =============================================
-- PART 2: CONVERTING TEXT TO DATE FORMAT
-- =============================================
alter table sales 
add column sales_date date ; 

update sales 
set sales_date = str_to_date(date ,'%m/%d/%Y' ) 
WHERE sales_date IS NULL
limit 100000;

alter table sales 
drop column date ;

alter table stores 
modify column Store_Open_Date date ; 

-- =============================================
-- PART 3 : CONVERT TEXT TO PRICE
-- =============================================
   -- 3.1 Clean symbols and spaces

update products 
set product_cost = replace ( product_Cost , '$' , '' ) ;

update products 
set product_price = replace (product_price , '$' , '' ) ; 

     -- 3.2 Convert to DECIMAL 
     
alter table products 
modify column Product_Cost decimal (10,2),
modify column Product_price decimal (10,2) ; 

--  check zero or negative prices 
select product_price from products 
where product_price = 0 ;  

select product_price from products 
where product_price < 0 ;  

 -- check negative sales quantities 
 select unit from sales 
 where unit < 0 ; 
 
 -- Are store inventory levels consistent with actual sales?
 
 with store_sales_stock as ( select  store_name , sum(unit) as total_sales_90d , sum(stock_on_hand) as current_stock   from store_sales_products s  
 join inventory i on i.Store_ID = s.store_id 
 where sales_date > date_sub((select max(sales_date) from store_sales_products ) , interval 90 day ) 
 group by store_name ) 
 select * ,  case when total_sales_90d = 0 or current_stock = 0 then 'NO ACTIVITY - Check store'
                  when current_stock > total_sales_90d * 10 then 'OVERSTOCK - Too much inventory'
                  when current_stock < total_sales_90d * 2 then 'LOW STOCK - Risk of stockout'
                  when total_sales_90d between current_stock * 0.8 and current_stock * 1.2 then 'CONSISTENT - Good match'
        ELSE 'ANALYZE - Further review needed'
    end as  stock_consistency_status 
    from store_sales_stock ;
    
      -- Sales & Revenue--
      create view  store_sales_products as 
      select s.Sale_ID ,
		s.store_ID ,
        s.product_ID ,
        s.unit,
        s.Sales_date, 
        o.store_name ,
        o.store_city ,
        o.Store_Location,
        o.Store_Open_Date,
        p.Product_Name,
        p.Product_Category,
        p.Product_Cost,
        p.Product_price
    from sales s 
    join stores o  on s.Store_ID = o.Store_ID 
    join products p on s.Product_ID = p.Product_ID ; 

            -- 1. total revenue for each year
            
select year ( sales_date ) as year ,
	sum( unit * product_price ) as total 
from sales s 
join products p on p.Product_ID = s.Product_ID
group by year(sales_date) ; 
 
            -- 2. How do sales change month by month? 
		
	with month_revenue as ( select year(sales_date) as year ,  
								   month(sales_date) as month ,
								    sum(unit*product_price) as revenue_per_month 
								   from store_sales_products 
                                    group by year(sales_date) , month(sales_date) ) 
            select * ,
                   revenue_per_month - lag (revenue_per_month) over ( order by year, month ) as monthly_change
            from month_revenue ; 

			-- 3. top 5 products that generate the most revenue

select p.product_name , sum(product_price * unit ) as revenue
from sales s
join products p on p.Product_ID = s.Product_ID
group by p.product_name 
order by sum(product_price * unit ) desc
limit 5 ;

              -- 4. products that represent 80% of total revenue 
		
		with revenue_products as ( select product_name,
			                               sum( unit*product_price) as revenue_per_product 
		                           from store_sales_products 
                                   group by product_name 
								   order by revenue_per_product desc) ,
        ranked_products as ( select * , 
			                       sum(revenue_per_product ) over ( order by revenue_per_product desc) as cumulative_revenue ,
									SUM(revenue_per_product) OVER () AS total_revenue
		                       from revenue_products ) 
        select  * , 
			   round( cumulative_revenue /total_revenue *100,2) as cumulative_percent
		from ranked_products 
        where round(cumulative_revenue /total_revenue *100,2) <= 80 ; 

              -- 5.  the average value per order 
      
	select sale_ID , avg (unit*product_price ) average_per_order  
    from store_sales_products 
    group by sale_ID ; 
    
             -- 6. How is revenue distributed across price ranges ? 
	WITH price_ranges AS (
    SELECT 
        CASE 
            WHEN product_price <= 10 THEN 'Low price'
            WHEN product_price <= 30 THEN 'Medium price'
            ELSE 'High price'
        END AS price_range,
        unit * product_price AS revenue
    FROM store_sales_products )
SELECT 
    price_range,
    ROUND(SUM(revenue), 2) AS total_revenue,
    ROUND(SUM(revenue) / (SELECT SUM(revenue) FROM price_ranges) * 100, 2) AS percentage_of_total
FROM price_ranges
GROUP BY price_range
ORDER BY total_revenue DESC;
			
     --  Product Analysis -- 
           -- 7.  products sell a lot but make very little profit 
SELECT 
    Product_Name,
    sum( unit * Product_Price) AS revenue,
    sum( unit ) as total_units_sold ,
    sum(unit * (Product_Price - Product_Cost)) as total_profit ,
   round( AVG(product_price - product_cost),2) as unit_profit_margin
from store_sales_products
group by Product_Name 
having SUM(unit) > 5000 AND SUM(unit * (product_price - product_cost)) < 20000 
ORDER BY total_units_sold DESC ; 
        
           -- 8.   the 10 least sold products 
           
	select Product_Name ,
		   sum(unit) as sold
    from store_sales_products 
    group by Product_Name 
    order by sum(unit) asc 
    limit 10 ; 
    
	       -- 9. product category that  is the most profitable 
           
select Product_Category , 
	   sum(unit* ( product_price - product_cost )) as total_profit 
from store_sales_products 
group by Product_Category
order by total_profit desc 
limit 1 ; 
        
         -- 10.  products that are seeing a decline in sales over the last 3 months 
	WITH sales_3_months AS ( SELECT
        product_name,
        DATE_FORMAT(sales_date, '%Y-%m') AS month_year,
        COUNT(*) AS sales
    FROM store_sales_products
    WHERE sales_date >= DATE_SUB((SELECT MAX(sales_date) FROM store_sales_products), INTERVAL 3 MONTH)
    GROUP BY product_name, DATE_FORMAT(sales_date, '%Y-%m') )

SELECT *
FROM (SELECT
        product_name,
        month_year,
        sales,
        LAG(sales) OVER ( PARTITION BY product_name ORDER BY month_year) AS previous_month_sales
         FROM sales_3_months) t
WHERE sales < previous_month_sales ;
    
		 -- 11.  product that have the best profit margin 
         
	select  product_name , 
                 round(avg ((product_price - product_cost)/ product_price *100 )) as profit_margin_percent 
	from store_sales_products 
	group by product_name 
	order by profit_margin_percent desc 
	limit 1 ;
         
		-- 12. the average price per product category
        
	select p.Product_Category ,  
    round (avg(Product_price), 2 ) AS average_per_category from  products p
    group by p.Product_Category
    order by round (avg(Product_price), 2 ) desc ;
     
     -- Store Analysis -- 
    
     -- 13. store that generates the most revenue 
     
	select r.Store_Name ,
           sum(unit* r.product_price ) as revenue_store
    from  store_sales_products r
    group by r.Store_Name
    order by sum(unit* r.product_price ) desc 
    limit 1 ; 
    
    -- 14. rank stores from best to worst performance
    
    select store_name , rank() over( order by revenue_store desc ) as rank_store
    from ( select r.Store_Name , sum(unit* r.product_price ) as revenue_store
           from  store_sales_products r
           group by r.Store_Name) as store_revenue ;
           
	-- 15. stores that sell below the national average 
    
    With store_revenue as (
    select store_name , 
		   sum(Unit*product_price) as revenue_per_store 
    from store_sales_products 
    group by store_name ) 
    select * from store_revenue 
    where revenue_per_store   < (select avg (revenue_per_store ) as national_avg from store_revenue) ; 
    
    -- 16. city that sells the most
      
	select store_city ,
		sum(unit* r.product_price ) as total_revenue_per_city
    from store_sales_products r
    group by store_city
    order by sum(unit* r.product_price ) desc
    limit 1 ; 
    
     -- 17. the performance gap between the best and worst store 
     
 with stores_revenue as (select store_name , 
								sum(unit*product_price ) as revenue_per_store 
                        from store_sales_products 
						group by store_name ) 
    select max(revenue_per_store) - min( revenue_per_store ) as gap_performance 
    from stores_revenue ;
    
    -- 18. Do older stores sell more than newer ones? 
    
  with sales_store as (  select store_name , store_open_date , sum(unit*product_price ) as total_revenue
    from store_sales_products 
    group by store_name , store_open_date
    order by store_open_date asc ) 
    select * , case when total_revenue > lag(total_revenue) over (order by store_open_date ) then  'Newer store sells more' 
                    when total_revenue < lag(total_revenue) over (order by store_open_date ) then 'Older store sells more'
				 ELSE 'Comparison not available' 
			end as comparison 
    from sales_store ; 
    -- Time Analysis --
       -- 19. months that have the highest sales
       
     SELECT 
        MONTH(sales_date) AS month,
        SUM(unit * product_price) AS monthly_revenue,
        RANK() OVER ( ORDER BY SUM(unit * product_price) DESC) AS rank_month
    FROM store_sales_products
    GROUP BY  MONTH(sales_date) ; 
    
	  -- 20. Are there specific times of year when sales are always strong?
      
 with sales_year as (select year(sales_date) as year ,
        month (sales_date) as month ,
        sum(unit*product_price)as sales 
        from store_sales_products 
        group by year(sales_date) , month (sales_date) ) , 
 ranked_sales as ( select * , 
                  rank() over (partition by year order by sales desc ) as ranking
                 from  sales_year ) 
    select month ,
		  count(*) as years_in_top_3 
    from ranked_sales
    where ranking <= 3 
    group by month 
    HAVING COUNT(*) = (SELECT COUNT(DISTINCT year) FROM sales_year)
	ORDER BY years_in_top_3 DESC ; 
   
     -- 21. the day of the week that generates the most sales
     select 
			dayname( sales_date ) as day_name ,
			SUM(unit * product_price) AS dayly_revenue,
			RANK() OVER ( ORDER BY SUM(unit * product_price) DESC) AS rank_day
    FROM store_sales_products
    GROUP BY  dayname(sales_date) ;
     
     -- 22. Are sales increasing or decreasing over the last 12 months? 
     
    with revenue_per_month as (  select DATE_FORMAT(sales_date, '%Y-%m') AS month  , sum(unit*product_price) as revenue 
     from store_sales_products 
     where sales_date >= DATE_SUB((SELECT MAX(sales_date) FROM store_sales_products), INTERVAL 12 MONTH)
     group by  month
     order by  month desc ) 
      select ( select revenue from revenue_per_month order by month desc limit 1 ) as firstvalue ,
              ( select revenue from revenue_per_month order by month asc limit 1 ) as lastvalue , 
              case when ( select revenue from revenue_per_month order by month desc limit 1 ) >
                         ( select revenue from revenue_per_month order by month asc limit 1 ) then 'increasing' 
                   else 'decreasing' 
	      end as trend; 
          
          -- 23. Which products sell mainly during certain seasons?
          
          select distinct unit from store_sales_products ;
		with sales_number_product as (  select product_name ,
											   MONTHNAME(sales_date) AS month_name , 
                                               date_format( sales_date , '%m') as month_num  ,
                                               sum(unit) as sales  
                                        from store_sales_products 
                                        group by product_name ,month_name , month_num )  , 
		avg_month as ( select product_name , 
					   month_name , 
					   sales  ,
                       avg(sales) over ( partition by product_name )  as average
					  from sales_number_product ) , 
      ranked as ( select * , 
                         rank () over ( partition by product_name order by sales desc ) as ranking 
				 from avg_month
        where sales > average) 
        select product_name,
               month_name AS peak_season,
               sales AS sales_in_peak , 
               ROUND(average, 2) AS avg_sales
		from  ranked
        where ranking = 1 ; 
          -- 24 . the best time of year to run promotions 
           
		with month_revenue as (select month(sales_date ) as month , 
                                      sum(unit*product_price) as revenue 
								from store_sales_products 
							    group by  month ) , 
       ranked as ( select * , 
                         rank () over (  order by revenue asc ) as ranking 
                  from month_revenue ) 
        select month , 
			revenue , 
              case when ranking = 1 then '  Run promotion to ATTRACT customers' 
	               when ranking = 12  then ' Run promotion to BOOST sales' 
	         end as promotion_strategy
         from ranked 
        where ranking in (1 , 12 ) 
        order by revenue desc ;
    
    --  Inventory Analysis -- 
	      -- 25.  products that are at risk of running out of stock 
          
    with inventory_product_store as ( 
    select i.Stock_On_Hand ,
           p.Product_Name 
    from inventory i
    join products p  on p.Product_ID = i.Product_ID )
    select product_name , 
           sum(stock_on_hand ) as total_stock ,
     case  when sum(stock_on_hand ) < 200 then  'Immediate reorder'
			when sum(stock_on_hand ) < 500 then 'Running out soon' 
		    else 'OK' 
		end as status 
		from inventory_product_store 
        group by product_name
        having sum(stock_on_hand ) < 500 ; 
        
        -- 26. products that have too much stock that doesn't move  
        
		WITH stock_per_product AS (  select  product_id, 
                                          SUM(stock_on_hand) as total_stock
                                    from inventory
									group by  product_id ),
sales_per_product AS (select product_id,
                             SUM(unit) AS total_sold
                       from sales
                       where sales_date >= DATE_SUB((select MAX(sales_date) from sales), INTERVAL 90 day)
                       group by  product_id )
SELECT p.product_name,
        s.total_stock,
        coalesce (sp.total_sold, 0) AS units_sold_90d
from products p
join stock_per_product s on p.product_id = s.product_id
LEFT JOIN sales_per_product sp on p.product_id = sp.product_id 
where s.total_stock > COALESCE(sp.total_sold, 0) * 5
order by s.total_stock desc ;
        
	
        -- 27. How quickly does inventory turn over per product? 
        
       with stock_per_product as ( select product_id , sum( stock_on_hand) as total_stock 
                                    from inventory 
                                    group by product_id)  ,
       monthly_sales as  (select product_id ,
								 product_name  , 
                                 year(sales_date) as year , 
								 month(sales_date) as month , 
								sum(unit) as  number_of_sales 
							from store_sales_products 
							group by product_id , product_name , month , year ) , 
       avg_monthly_sales as (  select product_id ,
                                      product_name ,
									  avg(number_of_sales) as average 
                               from monthly_sales 
                               group by product_id , product_name ) 
        select product_name , 
			   s.total_stock ,
               COALESCE(average , 0) as avg_monthly_sales,
              CASE 
                  WHEN s.total_stock / NULLIF(average , 0) < 3 THEN 'Fast-moving inventory'
				  WHEN s.total_stock / NULLIF(average , 0) BETWEEN 3 AND 6 THEN ' Average turnover'
				  WHEN s.total_stock / NULLIF(average , 0) > 6 THEN 'Slow-moving inventory'
                  ELSE ' No sales - Dead stock' end as turnover_status
		from stock_per_product s
		left join avg_monthly_sales p on p.product_id= s.product_id  ; 
        
        
		-- 28.  products that need to be reordered urgently 
with inventory_product_store as ( 
    select i.Stock_On_Hand ,
           p.Product_Name 
    from inventory i
    join products p  on p.Product_ID = i.Product_ID ) 
    select product_name , 
          sum( stock_on_hand ) as total_stock ,
           'Need immediate reorder' AS action_required  
	from inventory_product_store 
    group by product_name 
    having sum( stock_on_hand ) < 200 ; 
    
       -- 29 .products that haven't been sold in over 90 days 
       
	with sold_last_90_days AS (
    Select  DISTINCT product_id
    from  sales
    where sales_date >= DATE_SUB((Select MAX(sales_date) FROM sales), Interval 90 day ))
select  
    product_id,
    product_name
From products
Where product_id not in  (Select product_id From sold_last_90_days);
       
       -- 30.  How much does unsold inventory cost per store?
	with products_not_sold_90d AS ( select distinct  product_id
                                    from products
                                    where product_id not in (select distinct product_id
															from store_sales_products
                                                             where sales_date >= DATE_SUB((select MAX(sales_date) from  store_sales_products), INTERVAL 90 DAY))),
unsold_inventory AS (select i.store_id,
                            i.product_id,
                            i.stock_on_hand,
                            p.product_cost,
                              (i.stock_on_hand * p.product_cost) AS dead_stock_value
				  from inventory i
				  join products_not_sold_90d n on i.product_id = n.product_id
			      join products p on i.product_id = p.product_id)
select  s.store_name, u.store_id,
         ROUND(SUM(u.dead_stock_value), 2) as total_dead_stock_cost,
            SUM(u.stock_on_hand) as total_unsold_units
from unsold_inventory u
join stores s ON s.store_id = u.store_id
group by  u.store_id, s.store_name
order by  total_dead_stock_cost desc;
				
    
	   -- 31. For each category, what is the product ranking by revenue

select product_category ,
       product_name , 
       rank() over (partition by product_category order by sum(unit*product_price) desc ) rank_product_category  
from store_sales_products 
group by product_category , product_name ; 
    
        -- 32.  What are the top 3 products in each store? 
        
         select * 
         from (select store_ID , 
                    product_name , 
                    sum(unit*product_price) as revenue,
		            rank ()  over ( partition by store_ID order by sum(unit*product_price)  desc ) as rank_product 
        from store_sales_products 
        group by store_ID , product_name ) t
        where rank_product  <= 3; 
        
        -- 33. How do last month sales compare to previous month?

with monthly_revenue as (  select date_format(sales_date , '%y-%m') as month , 
								sum(unit*product_price ) as revenue 
                        from store_sales_products 
                        where sales_date >= date_sub((select max(sales_date) from store_sales_products), interval 2 month ) 
						group by month
                        order by month desc
                        limit 2 ) 
Select 
    case When MAX(CASE WHEN month = (SELECT MAX(month) FROM monthly_revenue) THEN revenue END) >
             MAX(CASE WHEN month = (SELECT MIN(month) FROM monthly_revenue) THEN revenue END) 
        then 'Increasing'
        Else 'Decreasing'
    End AS trend,
    (Select revenue FROM monthly_revenue ORDER BY month DESC LIMIT 1) AS last_month,
    (Select revenue FROM monthly_revenue ORDER BY month ASC LIMIT 1) AS previous_month
FROM monthly_revenue;
		
		        -- 34. What market share does each product represent?
                
        with product_revenue AS (select product_name,
                                       SUM(units * product_price) AS revenue
                                 from store_sales_products
                                 group by  product_name )
SELECT product_name,revenue,
        ROUND(revenue / SUM(revenue) over () * 100, 2) as market_share_percent
from product_revenue
order by revenue desc;

				-- 35. products that sell above the overall average 
  with product_revenue as
           (select product_name , sum(unit*product_price) as revenue 
           from store_sales_products
           group by  product_name ) 
  select product_name ,  revenue from product_revenue 
  where revenue > (select round (avg(revenue),2 )  as overall_avg from product_revenue) ; 
  
            -- 36 . What is the median sales value per category?
          with number_sales_product as ( select sales_date , 
                                         product_category , 
                                         count(*) as number from store_sales_products 
										group by sales_date , product_category) , 
		ranking as (  select product_category , 
					  number ,
                      row_number() over ( partition by product_category order by number asc  ) as numbering  , 
                      count(*) over  ( partition by product_category order by number asc  ) as cnt 
         from number_sales_product ) 
         select product_category , 
                avg (number)  AS MEDIAN from ranking
			where numbering in (floor((cnt + 1 )/ 2 ) , floor(cnt +2/ 2) )
            group by product_category ;

            -- 37. How do sales accumulate month after month since the beginning?
            
  with monthly_revenue  as ( select year (sales_date) as year , 
                                    month(sales_date) as month ,
									sum(unit*product_price ) as revenue_per_month
                             from store_sales_products 
                             group by year , month ) 
  select * , sum(revenue_per_month) over(order by year , month asc ) as running_total 
from monthly_revenue ; 
  
  -- Strategic Business Decisions--
            -- 38. What factors drive sales growth the most?
                   -- Identify best-performing stores and cities--
                   
            select store_name ,store_city ,  sum(unit*product_price) as revenue
            from store_sales_products 
            group by store_name , store_city 
            order by revenue desc ; 
                     -- Identify most profitable months--
                     
            select monthname(sales_date) as month , sum(unit*product_price) as revenue 
            from store_sales_products 
            group by month 
            order by revenue desc ;  
                    --  top-selling products --
            
		    select product_name , sum(unit*product_price) as revenue 
            from store_sales_products 
            group by product_name 
            order by revenue desc ; 
                    -- Analyze revenue by price brackets --
            
            select case WHEN product_price < 10 THEN 'Low '
						WHEN product_price < 30 THEN 'Medium '
						WHEN product_price < 50 THEN 'High'
						ELSE 'Premium (50€+)'
					END AS price_range,
            sum(unit*product_price) as revenue
            from store_sales_products 
            group by  price_range 
            order by revenue desc ; 
                 -- Analyze revenue by cost brackets -- 
            
            select case when product_cost < 5 THEN 'Low cost'
						WHEN product_cost < 15 THEN 'Medium cost'
                       ELSE 'High cost'
                    END AS cost_range,
				sum(unit*product_price) as revenue from store_sales_products 
			group by cost_range 
            order by revenue desc ; 
                  -- Compare all factors 
                  
            with ranked_factors as  ( Select 'Store' AS factor, store_name AS value, ROUND(SUM(unit* product_price), 2) AS revenue
                                      from  store_sales_products 
                                      GROUP BY store_name
                 UNION ALL
                                    Select 'Month' AS factor, MONTHNAME(sales_date) AS value, ROUND(SUM(unit* product_price), 2) AS revenue
                                    FROM store_sales_products 
                                     GROUP BY MONTHNAME(sales_date)
				UNION ALL
                                     select 'Category' AS factor, product_category AS value, ROUND(SUM(unit * product_price), 2) AS revenue
                                     FROM store_sales_products 
                                      group by  product_category),
 ranked as (select factor, value AS top_value, revenue,
                    rank() Over (partition by  factor order by  revenue desc) AS rank_in_factor
             from ranked_factors
             order by  factor, rank_in_factor ) 
select * from ranked 
where rank_in_factor <= 3  ; 

             -- 39 . Which products should be discontinued (low sales + low profit)?
with status_revenue as ( select product_id ,   product_name , sum(unit*product_price ) as total_revenue  , 
  case when sum(unit*product_price ) < 10000 then 'low_sales' 
	  when sum(unit*product_price ) < 30000 then 'medium_sales' 
      else 'high_revenue' 
	end as revenue_status
from store_sales_products 
group by product_id , product_name ) , 
status_profit as ( select  product_id  ,  AVG(product_price - product_cost)  as profit ,
	                      case when AVG(product_price - product_cost) < 3 then 'low_profit'
								when AVG(product_price - product_cost) < 8 then 'medium_profit'
                                else 'high_profit' 
						 end as profit_status
  from store_sales_products 
  group by product_id  ) 
  select p.product_name ,total_revenue , profit , profit_status ,revenue_status from products p 
  join status_revenue s on s.product_id = p.product_id 
  left join status_profit n on n.product_id = p.product_id 
  where profit_status = 'low_profit' and revenue_status = 'low_sales'  ;  
  
			-- 40 .Which stores should be closed or relocated? 
		select store_name, store_city,
				SUM(unit * product_price) AS total_revenue,
                SUM(unit * (product_price - product_cost)) AS total_profit,
                ROUND(SUM(unit* (product_price - product_cost)) / NULLIF(SUM(unit * product_price), 0) * 100, 2) as profit_margin_percent,
    CASE 
        when SUM(unit* product_price) < 400000 THEN 'Consider closing'
        when SUM(unit * product_price) < 600000 THEN ' relocated'
        else 'keep open '
    end as  recommendation
from  store_sales_products 
group by  store_name, store_city
having SUM(unit* product_price) < 400000
Order by  total_revenue asc ;

            -- 41. Which city would be profitable to open a new store?
		WITH city_analysis AS (
    select store_city, count(DISTINCT store_id) AS number_of_stores,
        count(DISTINCT sale_id) AS number_of_transactions,
        sum (unit) AS total_units_sold,
        ROUND(sum(unit* product_price), 2) AS total_revenue,
        round(sum(unit* (product_price - product_cost)), 2) AS total_profit,
        round(sum(unit* (product_price - product_cost)) / nullif (SUM(unit* product_price), 0) * 100, 2) AS profit_margin_percent,
        ROUND(SUM(unit* product_price) / count(DISTINCT store_id), 2) AS avg_revenue_per_store,
        ROUND(SUM(unit* (product_price - product_cost)) / count(DISTINCT store_id), 2) AS avg_profit_per_store
    from store_sales_products 
    group by  store_city )
select store_city, number_of_stores, number_of_transactions,
    total_revenue, total_profit, profit_margin_percent,
    avg_revenue_per_store,
    avg_profit_per_store,
    CASE 
        WHEN total_profit > 80000 AND number_of_stores <= 2 THEN 'HIGH POTENTIAL - Open new store'
        when total_profit > 60000 and number_of_stores <= 3 then 'GROWTH OPPORTUNITY - Consider expansion'
        when total_profit > 60000 and number_of_stores > 3 THEN ' SATURATED - Market may be saturated'
        when total_profit BETWEEN 30000 and 60000 THEN 'MODERATE - Need more analysis'
        when total_profit < 30000 and number_of_stores >= 2 then 'RISKY - Market might be weak'
        else 'INCONCLUSIVE - Further study needed'
    end AS expansion_decision,
    case 
        WHEN total_profit > 80000 AND number_of_stores <= 2 THEN 'PRIORITY 1 - High potential'
        WHEN total_profit > 60000 AND number_of_stores <= 3 THEN 'PRIORITY 2 - Growth opportunity'
        ELSE 'PRIORITY 3 - Low priority'
    end AS priority
from city_analysis
Where total_profit > 60000
Order by  total_profit desc ;

			-- 42. Which products should be promoted (good margin but slow sales)? 
         with profit_margin_revenue as (    select product_name , 
            round(sum(unit*product_price),2) as revenue ,
            round(sum(unit*(product_price-product_cost) ) ,2 ) as profit , 
			round (sum( unit*(product_price-product_cost)) /nullif(sum(unit*product_price) ,0)* 100,2) as margin_profit 
            from store_sales_products
            group by product_name ) 
		select * , case when revenue < 50000 and margin_profit  > 50 then 'promoted' 
                        else 'not promoted' 
					end as descision , 
				 case when margin_profit > 70 then 'PRIORITY 1 - Best margin'
                      when margin_profit > 60 then  'PRIORITY 2 - Great margin'
                 else 'PRIORITY 3 - Good margin'
                end as  priority
				from profit_margin_revenue 
                where revenue < 50000 and margin_profit  > 50
                order by  margin_profit Desc, revenue Asc ; 
            
 