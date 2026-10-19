# Databricks notebook source
dbutils.widgets.text("env", "dev")
env = dbutils.widgets.get("env")
print(f"segment_calc running in {env}")
